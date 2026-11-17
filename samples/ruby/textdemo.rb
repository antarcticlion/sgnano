# Text attributes demo (2026-10-16): colors, reverse, blink, lines, bold, rotation, double size,
# with ANSI escape sequences and with Machine.text_attr / text_put. Any key ends it.
M = Machine
M.mode = 1
M.text_clear
puts "\e[1;97mText attributes\e[0m  (ANSI escapes in puts, Machine.text_attr, Machine.text_put)"
puts
print "ANSI: "
print "\e[31mred \e[32mgreen \e[33myellow \e[34mblue \e[35mmagenta \e[36mcyan \e[37mwhite\e[0m  "
puts "\e[91mbright \e[92mcolors \e[96mtoo\e[0m"
print "      \e[7m reverse \e[0m \e[5mblink\e[0m \e[4munderline\e[0m \e[9mstrike\e[0m \e[53moverline\e[0m \e[1mbold\e[0m "
puts "\e[30;46m black on cyan \e[0m"
puts
# the 16 colors as backgrounds
print "16 colors: "
16.times { |i| M.text_attr = M.tattr(i == 0 || i == 8 ? 15 : 0, i); print format(" %2d ", i) }
M.text_attr = M::TEXT_DEFAULT
puts
puts
# double size
M.text_attr = M.tattr(M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_DOUBLE_WIDTH)
print "WIDE "
M.text_attr = M.tattr(M::TEXT_BRIGHT_CYAN, 0, M::TEXT_DOUBLE_HEIGHT)
print "TALL "
M.text_attr = M.tattr(M::TEXT_BRIGHT_MAGENTA, 0, M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT)
print "BIG 大きい"
M.text_attr = M::TEXT_DEFAULT
puts
puts
# left / right lines (2026-10-27): screen-left / screen-right edges of each character
print "left / right: "
M.text_attr = M.tattr(M::TEXT_BRIGHT_WHITE, 0, M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE)
print "A"
M.text_attr = M::TEXT_DEFAULT
print "   left: "
M.text_attr = M.tattr(M::TEXT_BRIGHT_CYAN, 0, M::TEXT_LEFT_LINE)
print "B"
M.text_attr = M::TEXT_DEFAULT
print "   right: "
M.text_attr = M.tattr(M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_RIGHT_LINE)
print "C"
M.text_attr = M::TEXT_DEFAULT
puts
puts
# rotation and combinations, placed with text_put (the cursor does not move)
y = M.cursor[1]
M.text_put(0, y, "rotate:")
M.text_put(9, y, "ABC", M.tattr(15, 0, M::TEXT_ROT90))
M.text_put(13, y, "ABC", M.tattr(15, 0, M::TEXT_ROT180))
M.text_put(17, y, "ABC", M.tattr(15, 0, M::TEXT_ROT270))
M.text_put(23, y, "bold+under+over", M.tattr(M::TEXT_BRIGHT_GREEN, 1, M::TEXT_BOLD | M::TEXT_UNDERLINE | M::TEXT_OVERLINE))
M.text_put(41, y, "漢字も反転", M.tattr(M::TEXT_BRIGHT_WHITE, 0, M::TEXT_REVERSE))
M.text_put(54, y, "blinking!", M.tattr(M::TEXT_BRIGHT_RED, 0, M::TEXT_BLINK | M::TEXT_BOLD))
# kanji rotated (full-width characters turn too)
y += 2
M.text_put(0, y, "kanji:")
M.text_put(9, y, "漢字回転", M.tattr(M::TEXT_BRIGHT_YELLOW))
M.text_put(19, y, "漢字回転", M.tattr(M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT90))
M.text_put(29, y, "漢字回転", M.tattr(M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT180))
M.text_put(39, y, "漢字回転", M.tattr(M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT270))
M.text_put(49, y, "倍角", M.tattr(M::TEXT_BRIGHT_CYAN, 0, M::TEXT_ROT90 | M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT))
M.text_put(59, y, "太字", M.tattr(M::TEXT_BRIGHT_GREEN, 0, M::TEXT_ROT270 | M::TEXT_BOLD | M::TEXT_UNDERLINE))
M.locate(0, y + 2)
# a little status bar with text_put at the bottom row
bar = M.tattr(0, M::TEXT_CYAN)
M.text_put(0, 27, " " * 80, bar)
M.text_put(1, 27, "Machine.text_put(x, y, str, attr) -- press any key", bar)
n = 0
until M.key
  M.text_put(66, 27, format("frame %6d", n), bar)
  M.vsync
  n += 1
end
M.text_clear
puts "bye"
