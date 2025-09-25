#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'openssl'
require 'timeout'
require 'fileutils'
require 'optparse'

# ----------------------------
# Config (env overrides supported)
# ----------------------------
URL_BASE     = ENV.fetch('EC_M3U8_BASE', 'https://d1l0mq8050ivkk.cloudfront.net/out/v1/e6cd690f157845f6a2f922e488ab6107/index')
OUT_DIR      = ENV.fetch('EC_OUT_DIR',   '/Users/austinmayes/Desktop/EC_Live')
SEGMENTS_S   = (ENV['EC_SEGMENTS'] || '1-4') # e.g. "1-4" or "1,3"
FFSEG_SEC    = (ENV['EC_SEGMENT_SECONDS'] || '3600').to_i
UA           = ENV.fetch('EC_UA', 'ec-live-checker/cron (+ffmpeg)')
START_GAP_MS = (ENV['EC_START_GAP_MS'] || '400').to_i
FFMPEG_BIN   = ENV.fetch('FFMPEG_BIN', '/opt/homebrew/bin/ffmpeg') # set absolute path for cron

FileUtils.mkdir_p(OUT_DIR)

# ----------------------------
# Helpers
# ----------------------------
def seg_list(spec)
  return (1..4).to_a if spec.nil? || spec.strip.empty?
  spec.split(',').flat_map { |t|
    if t.include?('-')
      a, b = t.split('-', 2).map!(&:to_i)
      (a..b).to_a
    else
      [t.to_i]
    end
  }.uniq.sort
end

def playlist_url(segment)
  "#{URL_BASE}_#{segment}.m3u8"
end

HttpResp = Struct.new(:code, :body)

def http_get(url, open_to: 5, read_to: 5)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.open_timeout = open_to
  http.read_timeout = read_to
  # Optional: strict cert checks (default true)
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  req = Net::HTTP::Get.new(uri.request_uri)
  req['User-Agent'] = UA

  resp = http.request(req)
  HttpResp.new(resp.code.to_i, resp.body.to_s)
rescue StandardError => e
  HttpResp.new(nil, "ERROR: #{e.class}: #{e.message}")
end

def hls_like?(body)
  return false if body.nil? || body.empty?
  body.include?('#EXTM3U') && (body.include?('#EXT-X-MEDIA-SEQUENCE') || body.include?('#EXTINF:'))
end

def live?(segment, force: false)
  url = playlist_url(segment)
  puts "Checking #{url}…"
  return true if force

  Timeout.timeout(10) do
    resp = http_get(url)
    if resp.code == 200 && hls_like?(resp.body) && !resp.body.include?('#EXT-X-ENDLIST')
      puts "Stream #{segment} is LIVE"
      true
    else
      peek = resp.body.lines.first(3).map { _1.strip[0,200] }.join(' | ')
      puts "Stream #{segment} not live (code=#{resp.code}) — peek: #{peek}"
      false
    end
  end
rescue Timeout::Error
  puts "Stream #{segment}: request timed out"
  false
end

def pid_file(segment) = File.join(OUT_DIR, ".segment#{segment}.pid")

def save_pgid(segment, pgid)
  File.write(pid_file(segment), pgid.to_s)
end

def load_pgid(segment)
  return nil unless File.exist?(pid_file(segment))
  Integer(File.read(pid_file(segment)).strip) rescue nil
end

def clear_pgid(segment)
  File.delete(pid_file(segment)) if File.exist?(pid_file(segment))
end

# Check whole process group liveness
def group_alive?(pgid)
  Process.kill(0, -pgid)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

def recording?(segment)
  pgid = load_pgid(segment)
  return false unless pgid
  alive = group_alive?(pgid)
  clear_pgid(segment) unless alive
  alive
end

def start_recording(segment, loglevel: 'info')
  puts "Starting recording for segment #{segment}…"

  url      = playlist_url(segment)
  out_pat  = File.join(OUT_DIR, "segment#{segment}_%Y%m%d_%H%M%S.mp4")
  log_path = File.join(OUT_DIR, "segment#{segment}.log")

  cmd = [
    FFMPEG_BIN,
    '-loglevel', loglevel, '-hide_banner',
    # robust input params; harmless if CDN is perfect
    '-user_agent', UA,
    '-protocol_whitelist', 'file,crypto,data,subfile,http,https,tcp,tls',
    '-reconnect', '1', '-reconnect_streamed', '1',
    '-reconnect_on_network_error', '1', '-reconnect_delay_max', '2',
    # input
    '-i', url,
    # copy (no transcode)
    '-c', 'copy',
    # segment->mp4 with faststart per segment
    '-f', 'segment',
    '-segment_format', 'mp4',
    '-segment_format_options', 'movflags=+faststart',
    '-reset_timestamps', '1',
    '-segment_time', FFSEG_SEC.to_s,
    '-strftime', '1',
    out_pat
  ]

  io = File.open(log_path, 'a')
  pid = Process.spawn(
    *cmd,
    in: File::NULL, out: io, err: io,
    pgroup: true,
    close_others: true
  )
  pgid = Process.getpgid(pid)
  Process.detach(pid)
  io.close

  save_pgid(segment, pgid)
  puts "Recording started: segment #{segment} (pid #{pid}, pgid #{pgid})"
  pid
end

def wait_group_exit(pgid, timeout_s:, label:)
  deadline   = Time.now + timeout_s
  last_print = 0
  loop do
    return :exited unless group_alive?(pgid)
    now = Time.now.to_i
    if now != last_print
      puts "[#{label}] pgid=#{pgid} still running…"
      last_print = now
    end
    return :timeout if Time.now >= deadline
    sleep 0.5
  end
end

def deliver(sig, pgid)
  Process.kill(sig, -pgid)
  puts " sent #{sig} to process group #{pgid}"
  true
rescue Errno::ESRCH
  puts " group #{pgid} not found"
  false
rescue Errno::EPERM
  puts " no permission to signal group #{pgid} (#{sig})"
  false
end

def sh_kill(sig, pgid)
  system('/bin/kill', "-#{sig}", '--', "-#{pgid}")
  ok = $?.exitstatus == 0
  puts " fallback /bin/kill -#{sig} -#{pgid} => #{ok ? 'ok' : 'failed'}"
  ok
end

def stop_recording(segment)
  pgid = load_pgid(segment)
  unless pgid
    puts "No recording PID/PGID for segment #{segment}"
    return
  end

  leader_pid = pgid
  cmdline = `ps -o command= -p #{leader_pid}`.strip rescue 'n/a'
  puts "Stopping segment #{segment} (pgid #{pgid}, leader #{leader_pid}) #{cmdline == '' ? '' : "(#{cmdline})"}"

  [[:INT, 45], [:TERM, 8], [:KILL, 2]].each do |sig, wait_s|
    delivered = deliver(sig, pgid) || sh_kill(sig, pgid)
    status    = wait_group_exit(pgid, timeout_s: wait_s, label: sig)
    break if status == :exited || !delivered
  end

  clear_pgid(segment)
end

# ----------------------------
# CLI
# ----------------------------
opts = { action: nil, segments: seg_list(SEGMENTS_S), force: false }

OptionParser.new do |o|
  o.banner = "Usage: #{File.basename($PROGRAM_NAME)} [start|check|stop] [--segments 1-4|1,3] [--force]"
  o.on('--segments S', 'Segments (e.g. 1-4 or 1,3)') { |s| opts[:segments] = seg_list(s) }
  o.on('--force', 'Skip HLS validation and try anyway') { opts[:force] = true }
end.parse!

opts[:action] = ARGV.shift
abort "Action required: start | check | stop" unless %w[start check stop].include?(opts[:action])

case opts[:action]
when 'check', 'start'
  opts[:segments].each_with_index do |seg, idx|
    if live?(seg, force: opts[:force])
      if recording?(seg)
        puts "Already recording segment #{seg}"
      elsif opts[:action] == 'start'
        start_recording(seg)
      end
    else
      puts "Not recording segment #{seg}" if opts[:action] == 'check'
    end
    sleep(START_GAP_MS / 1000.0) if opts[:action] == 'start' && idx < opts[:segments].length - 1
  end
when 'stop'
  opts[:segments].each do |seg|
    recording?(seg) ? stop_recording(seg) : puts("No recorder running for segment #{seg}")
  end
end
