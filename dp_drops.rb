require 'csv'
require 'common'

PATH = ARGV[0]

servers = DataPacket.servers

# read and add column to CSV
table = CSV.table(PATH)

if false
  table[:id] = table[:metric].map do |metric|
    server = servers.find { |s| s["alias"] == metric }
    if server.nil?
      warn "No server found matching #{metric}"
      nil
    else
      server["name"]
    end
  end

  # rename metric to hostname
  table[:hostname] = table[:metric]
  table.delete(:metric)

  CSV.open(PATH, "w") do |csv|
    csv << table.headers
    table.each do |row|
      csv << row
    end
  end
else
  drops_by_time = {}
  table.each do |row|
    time = row[:time]
    drops = row[:drop]
    drops_by_time[time] ||= {count: 0, ids: []}
    drops_by_time[time][:count] += drops
    drops_by_time[time][:ids] << row[:id] unless row[:id].nil?
  end

  drops_by_time.each do |time, data|
    next if data[:ids].length <= 3
    puts "- Time: #{time}, Users Lost: #{data[:count]}, Impacted Nodes: #{data[:ids].join(", ")}"
  end
end
