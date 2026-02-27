require "active_support/time"

@shortcuts = {}

def schedule_shortcut(name, every)
  @shortcuts[name] = {
    every: every,
    last_run: Time.at(0),
    next_run: Time.now + every
  }
end

# scheduling
schedule_shortcut("Update Translations", 1.hour)
schedule_shortcut("Clear Cache", 2.hours)

puts "Going into loop to #{ @shortcuts.size } shortcuts: #{ @shortcuts.keys.join(", ") }"
loop do
  now = Time.now

  puts "Checking shortcuts at #{ now.strftime("%Y-%m-%d %H:%M:%S") }"
  @shortcuts.each do |name, info|
    if now >= info[:next_run]
      puts "Running shortcut: #{name}"
      system "shortcuts", "run", name

      info[:last_run] = now
      info[:next_run] = now + info[:every]
    end
  end

  sleep(30)
end
