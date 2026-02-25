#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'common/logging'
require 'openssl'
require 'timeout'
require 'fileutils'
require 'optparse'

# ----------------------------
# Config (env overrides supported)
# ----------------------------
URL_BASE     = ENV.fetch('EC_M3U8_BASE', 'https://d1l0mq8050ivkk.cloudfront.net/out/v1/e6cd690f157845f6a2f922e488ab6107/index')
OUT_DIR      = ENV.fetch('EC_OUT_DIR',   '/Users/austinmayes/Desktop/EC_Live')
FFSEG_SEC    = (ENV['EC_SEGMENT_SECONDS'] || '3600').to_i
UA           = ENV.fetch('EC_UA', 'ec-live-checker/cron (+ffmpeg)')
START_GAP_MS = (ENV['EC_START_GAP_MS'] || '400').to_i

FileUtils.mkdir_p(OUT_DIR)

# ----------------------------
# Helpers
# ----------------------------
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
    "ffmpeg",
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

info "EC Live Checker started. Waiting for commands…"

rec_thread = nil

loop do
  print "> "
  input = gets
  break if input.nil? # EOF

  cmd = input.strip.downcase
  case cmd
  when "record"
    # start record thread
    info "Starting recording thread"
    rec_thread&.kill
    rec_thread = Thread.new do
      loop do
        (1..4).each do |segment|
          info "Checking segment #{segment}…"
          if recording?(segment)
            info "Segment #{segment} is currently recording."
          elsif live?(segment)
            start_recording(segment)
          else
            info "Segment #{segment} is not live."
          end
        end
        sleep 60
      end
    end
  when "stop"
    info "Stopping recording thread"
    rec_thread&.kill
    rec_thread = nil
    (1..4).each do |segment|
      if recording?(segment)
        pgid = load_pgid(segment)
        if pgid
          info "Stopping recording for segment #{segment} (pgid #{pgid})"
          Process.kill('TERM', -pgid) rescue nil
          clear_pgid(segment)
        else
          info "No PID found for segment #{segment}, skipping stop"
        end
      else
        info "Segment #{segment} is not recording."
      end
    end
  when "check"
    (1..4).each do |segment|
      if live?(segment, force: true)
        info "Segment #{segment} is LIVE (forced check)"
      else
        info "Segment #{segment} is not live (forced check)"
      end
    end
  when "exit", "quit"
    info "Exiting EC Live Checker"
    break
  else
    puts "Unknown command: #{cmd}"
    puts "Available commands: record, stop, check, exit"
  end
end
