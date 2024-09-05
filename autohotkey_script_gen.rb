# Utilities for generating AutoHotkey scripts

$contents = ""
$indent_level = 0

def indent
  $indent_level += 2
end

def unindent
  $indent_level -= 2
end

def comment(msg)
  write "; " + msg
  new_line
end

def new_line(times = 1)
  $contents += "\n"*times
end

def write(str)
  $contents += (" "*$indent_level) + str
  new_line
end

def make_playbacks(name, keys, start_x, start_y)
  x = start_x
  y = start_y
  index = 0
  row = 1
  comment "- Start #{name} Playbacks"
  keys.each do |key|
    key = "`#{key}" if key == ";"
    write "#{key}:: ; Row #{row} Button #{index + 1}"
    indent
    write "Click,#{x},#{y}"
    unindent
    write "Return"
    index+=1
    x += 135
    if index > 5
      y += 85
      x = start_x
      index = 0
      row += 1
    end
    new_line
  end
  comment "- End #{name} Playbacks"
  new_line
end

# Header
write "#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases."
write "SendMode Input  ; Recommended for new scripts due to its superior speed and reliability."
write "SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory."
write "CoordMode, Mouse, Screen"
new_line(2)

# Caps Function Keys
write "#If GetKeyState(\"CapsLock\" , \"T\")"
indent
new_line
comment "-- BEGIN PLAYBACKS --"
make_playbacks "Top Left", %w(1 2 3 4 5 6 7 8 9 0 - =), 200,140
make_playbacks "Top Right", %w(q w e r t y u i o p [ ]), 1095,140
make_playbacks "Bottom Left", %w(a s d f g h j k l ; '), 200,380
make_playbacks "Bottom Right", %w(z x c v b n m . /), 1095,380
comment "-- END PLAYBACKS --"
unindent
write "#If"

new_line(2)

comment "-- Begin Helpers --"

# Rel This
write "+1:: ; Release this cuelist"
indent
write "Send, {Delete}"
write "Sleep 30"
write "Send, {Delete}"
write "Sleep 60"
write "Send rq"
write "Sleep 60"
write "Send {Enter}"
write "Sleep 1500"
write "Click,150,678"
write "Sleep,160"
write "Click,315,556 ; Add Macro"
write "Sleep,1500"
write "Click,406,698 ; Select Macro"
write "Sleep,1500"
write "Click,294,577 ; Dropdown"
write "Sleep,1500"
write "Click,241,852 ; Rel This"
write "Sleep,1500"
write "Click,809,570 ; Apply"
unindent
write "Return"

new_line

comment "-- End Helpers --"


File.open("/Users/austinmayes/Desktop/script", "w") { |f| f.write $contents }
