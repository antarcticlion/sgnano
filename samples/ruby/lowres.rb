# Lowres plane demo (2026-10-17): screen mode 3 (a CLUT8 framebuffer behind the lowres plane), 4 (CLUT4), 5 (no framebuffer) or 6
# (lowres only, 320x240 native timing). Change MODE below.
# FB: a gradient made of the default palette. Lowres BG1: a still star field; BG0: a scrolling checker floor;
# objects: 4 bouncing balls. Any key ends it.
# Load (measured 2026-10-17, the budget is 127 us a pair; usual / when the 4 balls meet on the same lines):
#   mode 3 about 82 / 112 us, mode 4 about 81 / 97 us, mode 5 about 61 us, mode 6 about 59 us.
# In mode 3 the program waits while the screen reads the framebuffer (most of the time); in mode 4 only about a tenth.
# More objects on the same lines, or scrolling both planes, go over the budget in mode 3 first.
MODE = 3                                # 3, 4, 5 or 6
M = Machine
M.mode = MODE
M.text_visible = false
fb = M.fb
lr = M.lowres
# --- framebuffer: sky gradient with the gray ramp (216..255) and a color band from the 6x6x6 cube
if MODE == 3
  40.times { |i| fb.fill_rect(0, i * 12, 640, 12, 216 + i) }
  6.times { |i| fb.fill_rect(i * 106, 400, 106, 80, 36 * i + 5) }
elsif MODE == 4                         # CLUT4: the 16 colors (PC-98) in bands
  40.times { |i| fb.fill_rect(0, i * 12, 640, 12, i % 2 == 0 ? 1 : 0) }
  8.times { |i| fb.fill_rect(i * 80, 400, 80, 80, 8 + i) }
end
# --- lowres palettes: 1 = floor, 2 = stars, 3.. = balls
lr.palette(1, 1, 40, 40, 120)
lr.palette(1, 2, 90, 90, 200)
lr.palette(2, 1, 255, 255, 255)
lr.palette(2, 2, 255, 255, 120)
cols = [[255, 80, 80], [80, 255, 80], [80, 160, 255], [255, 220, 60], [255, 120, 255], [80, 255, 255]]
cols.each_with_index do |c, i|
  lr.palette(3 + i, 1, c[0], c[1], c[2])
  lr.palette(3 + i, 2, 255, 255, 255)
  lr.palette(3 + i, 3, c[0] / 2, c[1] / 2, c[2] / 2)
end
# --- tiles: 1 = floor (2 colors checker), 2 = transparent, 3 = star
lr.pattern(1, Array.new(64) { |i| ((i / 8) / 4 + (i % 8) / 4) % 2 == 0 ? 1 : 2 })
lr.pattern(2, [128] * 64)
lr.pattern(3, Array.new(64) { |i| x = i % 8; y = i / 8; (x == 3 && y.between?(2, 4)) || (y == 3 && x.between?(2, 4)) ? 1 : 128 })
# a ball, 16x16 from tile 10 (256 bytes = 4 tiles): shaded with a highlight
lr.pattern(10, Array.new(256) { |i|
  x = i % 16 - 7.5; y = i / 16 - 7.5
  d = x * x + y * y
  if d >= 56 then 128
  elsif (x + 3)**2 + (y + 3)**2 < 6 then 2
  elsif d > 30 then 3
  else 1
  end
})
# BG0: floor in the lower part (rows 20.. of the map), transparent above; BG1: stars
lr.fill_map(0, 2)
64.times { |tx| (20...64).each { |ty| lr.map(0, tx, ty, 1, 1) } }
lr.fill_map(1, 2)
srand(7)
60.times { lr.map(1, rand(64), rand(30), 3, 2) }
# objects
balls = Array.new(4) { |i| [rand(300) + 4, rand(100) + 10, rand(5) - 2.5, 0.0, i % 6] }
balls.each_with_index { |b, i| lr.obj(i, b[0], b[1], 10, 16, 16, 3 + b[4]) }
M.clear_keys
t = 0
until M.key
  balls.each_with_index do |b, i|
    b[3] += 0.35                      # gravity
    b[0] += b[2]; b[1] += b[3]
    if b[1] > 144 then b[1] = 144; b[3] = -b[3] * 0.9 - 0.5 end   # bounce on the floor (y = 160)
    b[2] = -b[2] if b[0] < 0 || b[0] > 304
    lr.obj_move(i, b[0], b[1])
  end
  lr.scroll(0, t, 0)                  # the floor slides
  # BG1 (the stars) stays still: scrolling both planes with objects meeting on a line goes near the budget
  t += 2
  M.vsync
end
lr.clear
M.mode = 2
puts "bye"
