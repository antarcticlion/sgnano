# FONT DEMO (2026-11-02): every text decoration in one screen -- colours, bold,
# underline, strike, overline, reverse, blink, left/right border lines, rotation,
# double width/height, and the outer frame of doubled characters.
# The same layout is in samples/python/fontdemo.py and samples/basic/fontdemo.bas.
# Any key ends it. The status row shows a running frame number.
M = Machine
M.mode = 1
M.clear_keys
M.text_clear
W = M.text_cols

def put(x, y, s, a) = M.text_put(x, y, s, a)
def label(x, y, s) = M.text_put(x, y, s, M.tattr(M::TEXT_GRAY))
def tile(x, y, ch, fg, bg = 0, flags = 0) = M.text_put(x, y, ch, M.tattr(fg, bg, flags))
def flags(fg, bg, f) = M.tattr(fg, bg, f)

# A word with a box around the whole word: top/bottom on every cell, left on the
# first cell and right on the last cell.
def framed_word(x, y, s, fg, bg)
  n = s.length
  s.each_char.with_index do |ch, i|
    f = M::TEXT_OVERLINE | M::TEXT_UNDERLINE
    f |= M::TEXT_LEFT_LINE if i == 0
    f |= M::TEXT_RIGHT_LINE if i == n - 1
    M.text_put(x + i, y, ch, M.tattr(fg, bg, f))
  end
end

put(0, 0, "FONT DEMO  --  colours, styles, lines, rotation, double size",
    M.tattr(M::TEXT_BRIGHT_WHITE, 0, M::TEXT_BOLD))

# row 1: one flag each
label(0, 1, "normal");  tile(7, 1, "A", M::TEXT_BRIGHT_WHITE)
label(10, 1, "bold");   tile(15, 1, "B", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_BOLD)
label(18, 1, "under");  tile(24, 1, "C", M::TEXT_BRIGHT_CYAN, 0, M::TEXT_UNDERLINE)
label(27, 1, "strike"); tile(34, 1, "D", M::TEXT_BRIGHT_MAGENTA, 0, M::TEXT_STRIKE)
label(37, 1, "over");   tile(42, 1, "E", M::TEXT_BRIGHT_GREEN, 0, M::TEXT_OVERLINE)
label(45, 1, "reverse");tile(53, 1, "F", M::TEXT_BRIGHT_RED, 0, M::TEXT_REVERSE)
label(56, 1, "blink");  tile(62, 1, "G", M::TEXT_BRIGHT_CYAN, 0, M::TEXT_BLINK)

# row 2: left / right lines, a frame, and combinations
label(0, 2, "left");  tile(5, 2, "H", M::TEXT_BRIGHT_WHITE, 0, M::TEXT_LEFT_LINE)
label(8, 2, "right"); tile(14, 2, "I", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_RIGHT_LINE)
label(17, 2, "both"); tile(22, 2, "J", M::TEXT_BRIGHT_GREEN, 0, M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE)
label(25, 2, "frame")
framed_word(31, 2, "FRAME", M::TEXT_BRIGHT_WHITE, M::TEXT_BLUE)
label(40, 2, "bold+under+over"); tile(55, 2, "K", M::TEXT_BRIGHT_MAGENTA, 0, M::TEXT_BOLD | M::TEXT_UNDERLINE | M::TEXT_OVERLINE)
label(58, 2, "blink+bold");      tile(69, 2, "L", M::TEXT_BRIGHT_RED, 0, M::TEXT_BLINK | M::TEXT_BOLD)

# rows 3 / 4: the 16 colours as background and as foreground
label(0, 3, "bg colours:")
16.times do |i|
  fg = (i == 0 || i == 8) ? 15 : 0
  put(12 + i * 4, 3, format(" %X  ", i), M.tattr(fg, i))
end
label(0, 4, "fg colours:")
16.times do |i|
  bg = (i == 0) ? 7 : 0
  put(12 + i * 4, 4, format(" %X  ", i), M.tattr(i, bg))
end

# rows 5-6: double width / height / both
label(0, 5, "double:")
tile(9, 5, "WIDE", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_DOUBLE_WIDTH)
tile(18, 5, "TALL", M::TEXT_BRIGHT_CYAN, 0, M::TEXT_DOUBLE_HEIGHT)
tile(23, 5, "BOTH", M::TEXT_BRIGHT_MAGENTA, 0, M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT)
tile(32, 5, "漢", M::TEXT_BRIGHT_GREEN, 0, M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT)
tile(37, 5, "字", M::TEXT_BRIGHT_GREEN, 0, M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT)
label(0, 7, "double width / double height / both")

# rows 8-9: the outer frame of a doubled character (all four lines)
label(0, 8, "lines on double:")
tile(17, 8, "漢", M::TEXT_BRIGHT_WHITE, M::TEXT_BLUE,
     M::TEXT_DOUBLE_WIDTH | M::TEXT_DOUBLE_HEIGHT | M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE | M::TEXT_OVERLINE | M::TEXT_UNDERLINE)
label(22, 8, "outer frame")

# row 10: rotation and combinations
label(0, 10, "rotate:")
tile(8, 10, "A", M::TEXT_BRIGHT_WHITE, 0, M::TEXT_ROT90)
tile(10, 10, "B", M::TEXT_BRIGHT_WHITE, 0, M::TEXT_ROT180)
tile(12, 10, "C", M::TEXT_BRIGHT_WHITE, 0, M::TEXT_ROT270)
label(15, 10, "bold+under+over"); tile(30, 10, "D", M::TEXT_BRIGHT_GREEN, 0, M::TEXT_BOLD | M::TEXT_UNDERLINE | M::TEXT_OVERLINE)
label(33, 10, "reverse");         tile(41, 10, "漢字", M::TEXT_BRIGHT_WHITE, 0, M::TEXT_REVERSE)
label(46, 10, "blink");           tile(52, 10, "E", M::TEXT_BRIGHT_RED, 0, M::TEXT_BLINK | M::TEXT_BOLD)

# row 11: full-width kanji, each rotation
label(0, 11, "kanji:")
tile(7, 11, "漢字", M::TEXT_BRIGHT_YELLOW)
tile(13, 11, "漢字", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT90)
tile(19, 11, "漢字", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT180)
tile(25, 11, "漢字", M::TEXT_BRIGHT_YELLOW, 0, M::TEXT_ROT270)
label(31, 11, "left+right:"); tile(43, 11, "漢", M::TEXT_BRIGHT_CYAN, 0, M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE)

# row 12: boxes and other combinations
label(0, 12, "box:")
framed_word(5, 12, "ABCDE", M::TEXT_BRIGHT_WHITE, M::TEXT_BLUE)
label(13, 12, "left+right 漢:"); tile(29, 12, "漢", M::TEXT_BRIGHT_GREEN, 0,
                                      M::TEXT_LEFT_LINE | M::TEXT_RIGHT_LINE | M::TEXT_OVERLINE | M::TEXT_UNDERLINE)
label(34, 12, "blink+reverse:"); tile(48, 12, "F", M::TEXT_BRIGHT_RED, 0, M::TEXT_BLINK | M::TEXT_REVERSE)

# status row
bar = M.tattr(0, M::TEXT_CYAN)
M.text_put(0, 27, " " * W, bar)
M.text_put(1, 27, "FONT DEMO -- press any key to end", bar)
n = 0
while M.key.nil?
  M.text_put(64, 27, format("frame %6d", n), bar)
  M.vsync
  n += 1
end
M.text_clear
puts "fontdemo: bye"
