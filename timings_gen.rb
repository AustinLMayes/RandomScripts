# Generates timings for the user to follow based on keyboard input

require 'time'

puts "Press enter to log time, type 'exit' to quit"

times = []

while true
    input = gets.chomp
    break if input == "e"
    times << nil and next if input == "r"
    times << Time.now
end

last_time = nil
times.each_with_index do |time, i|
    if time.nil?
        puts ""
        last_time = nil
        next
    end
    diff = last_time ? time - last_time : 0
    puts "Followed @ #{diff.round(2)} s"
    last_time = time
end
