# Key input on sgnano (2026-10-16): lines from the keyboard (gets, STDIN) and single keys (Machine.key and friends).
# gets shows what you type on the terminal: BS erases, Enter ends the line, Ctrl-D at the start of a line is "end of input".
# ESC still stops the program, so it never reaches the program.
print "name? "
name = gets
p name
puts "hello, #{name.chomp}"
p gets
p STDIN.getc
p $stdin.read
p gets
p [Machine.key, Machine.key, Machine.key]
p [Machine.key_name(Machine::KEY_UP), Machine.key_name(65), Machine.key_name(3), Machine.key_name(Machine::KEY_F5), Machine.key_name(13)]
p [Machine.key_down?("a"), Machine.key_down?("A"), Machine.key_down?(Machine::KEY_SHIFT), Machine.key_down?("z"), Machine.keyboard?]
Machine.clear_keys
p Machine.key
puts "done"
