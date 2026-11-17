# Screen mode 7 (2026-10-23): text (25 rows) + a 320x200 bitmap, 1 byte per pixel (256-color palette).
# The same shape as VGA mode 13h. First it checks the drawing with pget/read, then shows a demo:
# the palette swatches, lines, a plasma and a rotating palette. q (or ESC) ends it; it also ends after about 10 seconds.
M = Machine
M.mode = 7
bm = M.bitmap
ng = 0
check = lambda do |what, got, want|
  if got != want
    puts "NG #{what}: got #{got.inspect}, want #{want.inspect}"
    ng += 1
  end
end

check.call("size", [bm.width, bm.height], [320, 200])
check.call("text rows", M.text_rows, 25)
bm.clear(0)
check.call("clear", bm.pget(319, 199), 0)
bm.pset(10, 20, 200)
check.call("pset", bm.pget(10, 20), 200)
check.call("pget outside", bm.pget(320, 0), nil)
bm.fill_rect(100, 50, 8, 4, 77)
check.call("fill_rect inside", bm.pget(107, 53), 77)
check.call("fill_rect edge", bm.pget(108, 53), 0)
bm.fill_rect(-5, -5, 10, 10, 5)          # clipped at the top-left corner
check.call("fill_rect clip", [bm.pget(0, 0), bm.pget(4, 4), bm.pget(5, 5)], [5, 5, 0])
bm.line(0, 199, 319, 0, 9)
check.call("line ends", [bm.pget(0, 199), bm.pget(319, 0)], [9, 9])
bm.rect(200, 100, 20, 10, 33)
check.call("rect", [bm.pget(200, 100), bm.pget(219, 109), bm.pget(210, 105)], [33, 33, 0])
check.call("write", bm.write(320 * 150 + 10, "\x01\x02\x03"), 3)
check.call("read", bm.read(320 * 150 + 10, 3).bytes, [1, 2, 3])
check.call("write at the end", bm.write(63999, "\x07\x08"), 1)
bm.palette(250, 255, 0, 0)
check.call("palette", bm.palette(250), [255, 0, 0])
check.call("default palette 15", bm.palette(15), [255, 255, 255])
begin
  bm.palette(256, 0, 0, 0)
  check.call("palette 256 raises", true, false)
rescue ArgumentError
end
puts ng == 0 ? "mode7 checks: all ok" : "mode7 checks: #{ng} NG"

# ---- demo ----
bm.clear(0)
16.times do |r|                          # the 256 colors as 16x16 swatches (8x6 each), at the top left
  16.times { |c| bm.fill_rect(c * 8, r * 6, 8, 6, r * 16 + c) }
end
# a plasma on the right that uses colors 16..231 (the 6x6x6 cube), drawn a row at a time with write
row = "\0" * 192
96.times do |y|
  192.times { |x| row.setbyte(x, 16 + ((x * 3 + y * 5 + (x * y) / 40) % 216)) }
  bm.write(y * 320 + 128, row)
end
20.times { |k| bm.line(0, 100 + k * 5, 319, 199 - k * 5, 232 + k) }
M.text_clear
M.text_put(0, 0, "SCREEN MODE 7  320x200x8 + text 80x25", M.tattr(15, 1))
M.text_put(0, 24, "q: quit   (the bottom text row is row 24)", M.tattr(14))
t0 = M.ms
f = 0
loop do
  break if M.key == "q".ord || M.ms - t0 > 10000
  M.vsync
  f += 1
  # turn the plasma colors (16..231) round: 216 palette writes a frame
  216.times do |i|
    c = (i + f) % 216
    bm.palette(16 + i, (c * 7) % 256, (c * 3) % 256, 255 - (c * 5) % 256)
  end
end
M.text_clear
puts "MODE7 done"
