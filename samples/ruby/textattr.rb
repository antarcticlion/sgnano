# Text attributes (2026-10-16): ANSI escape sequences in puts / print, Machine.text_attr, tattr, locate, text_put, text_get.
# Checks the terminal's cells with text_get; the results are printed at the end (printing moves the cursor).
$res = []
def check(name, cond)
  $res << [name, cond]
end
M = Machine
def at(x, y) = M.text_get(x, y)
def fg(a) = a & 15
def bg(a) = (a >> 4) & 15

M.text_clear
check "default attribute", M.text_attr == M::TEXT_DEFAULT
check "size", M.text_cols == 80 && M.text_rows == 28
check "cursor home", M.cursor == [0, 0]

# ANSI SGR
print "\e[1;31mR\e[0m"
c = at(0, 0)
check "SGR bold red", c[0] == "R" && fg(c[1]) == M::TEXT_RED && (c[1] & M::TEXT_BOLD) != 0
check "SGR 0 resets", M.text_attr == M::TEXT_DEFAULT
print "\e[7mV\e[27m\e[4mU\e[24m\e[5mB\e[25m\e[9mS\e[29m\e[53mO\e[55m"
check "reverse", (at(1, 0)[1] & M::TEXT_REVERSE) != 0
check "underline", (at(2, 0)[1] & M::TEXT_UNDERLINE) != 0
check "blink", (at(3, 0)[1] & M::TEXT_BLINK) != 0
check "strike", (at(4, 0)[1] & M::TEXT_STRIKE) != 0
check "overline", (at(5, 0)[1] & M::TEXT_OVERLINE) != 0
check "each attribute turned off again", M.text_attr == M::TEXT_DEFAULT
print "\e[92;44mG\e[39;49m"
check "bright green on blue", fg(at(6, 0)[1]) == M::TEXT_BRIGHT_GREEN && bg(at(6, 0)[1]) == M::TEXT_BLUE
check "39 / 49 back to default colors", M.text_attr == M::TEXT_DEFAULT

# left / right lines (2026-10-27)
M.text_put(0, 1, "L", M.tattr(M::TEXT_WHITE, 0, M::TEXT_LEFT_LINE))
M.text_put(1, 1, "R", M.tattr(M::TEXT_WHITE, 0, M::TEXT_RIGHT_LINE))
check "left line", (at(0, 1)[1] & M::TEXT_LEFT_LINE) != 0
check "right line", (at(1, 1)[1] & M::TEXT_RIGHT_LINE) != 0
begin
  M.tattr(15, 0, 0x02000000)
  check "tattr refuses bits above 24", false
rescue ArgumentError
  check "tattr refuses bits above 24", true
end

# cursor movement
print "\e[5;10HX"
check "ESC[row;colH", at(9, 4)[0] == "X" && M.cursor == [10, 4]
M.locate(70, 2)
print "abcdefghijKL"
check "wrap at 80 columns", at(79, 2)[0] == "j" && at(0, 3)[0] == "K" && M.cursor == [2, 3]
print "\e[3;1H\e[K"
check "ESC[K clears the line", at(0, 2)[0] == " " && at(79, 2)[0] == " "

# Machine.text_attr / text_color / tattr
M.text_clear
M.text_attr = M.tattr(M::TEXT_YELLOW, M::TEXT_RED, M::TEXT_BOLD | M::TEXT_UNDERLINE)
print "Y"
a = at(0, 0)[1]
check "text_attr= / tattr", fg(a) == M::TEXT_YELLOW && bg(a) == M::TEXT_RED && (a & M::TEXT_BOLD) != 0 && (a & M::TEXT_UNDERLINE) != 0
M.text_color(M::TEXT_CYAN)
print "C"
check "text_color keeps the other flags", fg(at(1, 0)[1]) == M::TEXT_CYAN && (at(1, 0)[1] & M::TEXT_BOLD) != 0
M.text_attr = M::TEXT_DEFAULT

# wide characters
M.locate(0, 1)
print "あい"
check "a wide character takes 2 cells", at(0, 1)[0] == "あ" && at(1, 1)[0] == "" && at(2, 1)[0] == "い" && M.cursor == [4, 1]

# double width / double height
M.locate(0, 4)
M.text_attr = M.tattr(M::TEXT_BRIGHT_WHITE, 0, M::TEXT_DOUBLE_WIDTH)
print "W"
check "double width: 2 cells", at(0, 4)[0] == "W" && at(1, 4)[0] == "" && M.cursor == [2, 4]
M.text_attr = M.tattr(M::TEXT_BRIGHT_WHITE, 0, M::TEXT_DOUBLE_HEIGHT)
print "H\n"
check "double height: the row below too", at(2, 4)[0] == "H" && at(2, 5)[0] == "H" && (at(2, 5)[1] & 0x200000) != 0
check "a newline after a tall row goes down 2 rows", M.cursor == [0, 6]
M.text_attr = M::TEXT_DEFAULT

# text_put: does not move the cursor, clips at the right edge
M.locate(3, 7)
n = M.text_put(76, 10, "12345", M.tattr(M::TEXT_GREEN))
check "text_put clips", n == 4 && at(79, 10)[0] == "4" && fg(at(79, 10)[1]) == M::TEXT_GREEN
check "text_put keeps the cursor", M.cursor == [3, 7]
M.text_put(0, 11, "rot", M.tattr(15, 0, M::TEXT_ROT90))
check "rotation flag", (at(0, 11)[1] & M::TEXT_ROT270) == M::TEXT_ROT90

# text_attr_at: rewrite only the attribute of one half-width cell of a doubled character
M.text_clear
base = M.tattr(M::TEXT_BRIGHT_WHITE, 0,
               M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT |
               M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE |
               M::TEXT_OVERLINE | M::TEXT_UNDERLINE)
M.text_put(10, 2, "\u6F22", base)                    # 4x2 cells: x=10..13, y=2..3
a = M.text_attr_at(10, 2, M.tattr(M::TEXT_BRIGHT_YELLOW, 1,
                                  M::TEXT_LEFT_LINE | M::TEXT_OVERLINE))
check "text_attr_at returns the new attribute", fg(a) == M::TEXT_BRIGHT_YELLOW && bg(a) == 1
check "text_attr_at keeps the double-size flags",
      (a & M::TEXT_DOUBLE_WIDTH) != 0 && (a & M::TEXT_DOUBLE_HEIGHT) != 0
check "text_attr_at replaces the line flags",
      (a & M::TEXT_LEFT_LINE) != 0 && (a & M::TEXT_OVERLINE) != 0 &&
      (a & M::TEXT_RIGHT_LINE) == 0 && (a & M::TEXT_UNDERLINE) == 0
check "text_attr_at keeps the glyph", at(10, 2)[0] == "\u6F22" && at(10, 3)[0] == "\u6F22"
check "text_attr_at keeps the full-width right mark", (at(11, 2)[1] & 0x100) != 0
check "text_attr_at keeps the lower / right marks",
      (at(10, 3)[1] & 0x200000) != 0 && (at(13, 3)[1] & 0x400000) != 0
b = M.text_attr_at(13, 3, M.tattr(M::TEXT_BRIGHT_CYAN, 0,
                                  M::TEXT_RIGHT_LINE | M::TEXT_UNDERLINE))
check "text_attr_at changes the bottom-right cell",
      fg(b) == M::TEXT_BRIGHT_CYAN && (b & M::TEXT_RIGHT_LINE) != 0 &&
      (b & M::TEXT_UNDERLINE) != 0 && (b & M::TEXT_LEFT_LINE) == 0
check "text_attr_at keeps the bottom-right marks",
      (b & 0x100) != 0 && (b & 0x200000) != 0 && (b & 0x400000) != 0
begin
  M.text_attr_at(80, 0, M.tattr(15))
  check "text_attr_at refuses x = 80", false
rescue ArgumentError
  check "text_attr_at refuses x = 80", true
end

# scrolling
M.text_clear
M.text_put(0, 0, "TOP")
30.times { |i| puts "line #{i}" }
check "scrolled: the first line went away", at(0, 0)[0] != "T"
check "scrolled: the last line is above the cursor", at(0, 26)[0] == "l" && at(5, 26)[0] == "2" && M.cursor == [0, 27]

begin
  M.tattr(16)
  check "tattr refuses color 16", false
rescue ArgumentError
  check "tattr refuses color 16", true
end
begin
  M.locate(80, 0)
  check "locate refuses x = 80", false
rescue ArgumentError
  check "locate refuses x = 80", true
end

M.text_clear
ng = 0
$res.each { |n, ok| puts "#{ok ? 'ok' : 'NG'} #{n}"; ng += 1 unless ok }
puts ng == 0 ? "all ok" : "#{ng} NG"
