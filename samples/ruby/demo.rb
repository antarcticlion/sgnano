# sgnano demo: about one minute of colorful drawing on screen mode 2.
# Scenes: title, starburst, bouncing lines, tunnel, spirograph, plasma, fireworks.
Machine.mode = 2
fb = Machine.fb
W = 640
H = 480

def rainbow(i)
  i = i % 256
  h = i * 6 / 256
  f = (i * 6) % 256
  case h
  when 0 then Machine.rgb(255, f, 0)
  when 1 then Machine.rgb(255 - f, 255, 0)
  when 2 then Machine.rgb(0, 255, f)
  when 3 then Machine.rgb(0, 255 - f, 255)
  when 4 then Machine.rgb(f, 0, 255)
  else Machine.rgb(255, 0, 255 - f)
  end
end
# (Array.new(n) { } ignores the block in mruby/c: fill the arrays with times)
PAL = Array.new(256, 0)
SIN = Array.new(256, 0)
256.times do |i|
  PAL[i] = rainbow(i)
  SIN[i] = (Math.sin(i * Math::PI / 128.0) * 127.0).to_i
end
def isin(i) = SIN[i % 256]
def icos(i) = SIN[(i + 64) % 256]

def scene_until(ms)
  t0 = Machine.ms
  frame = 0
  while Machine.ms - t0 < ms
    yield frame
    frame += 1
  end
end

# 1. title
fb.clear
240.times { |y| fb.fill_rect(0, y * 2, W, 2, Machine.rgb(y / 3, 0, 80 + y / 2)) }
Machine.text_visible = true
puts ""
puts "          *** sgnano  --  mruby/c on RP2350B ***"
puts ""
puts "          640 x 480  RGB555  /  Ruby drawing demo"
Machine.vsync(180)
Machine.text_visible = false

# 2. starburst
fb.clear
cx = W / 2
cy = H / 2
scene_until(8000) do |f|
  16.times do |k|
    a = f * 16 + k
    x = cx + icos(a) * 3
    y = cy + isin(a) * 2
    fb.line(cx, cy, x, y, PAL[(a * 3 + f * 5) % 256])
  end
end

# 3. bouncing lines with a trail
fb.clear
x1 = 100
y1 = 50
x2 = 500
y2 = 400
dx1 = 7
dy1 = 5
dx2 = -6
dy2 = 8
trail = []
scene_until(10000) do |f|
  8.times do |k|
    x1 += dx1
    y1 += dy1
    x2 += dx2
    y2 += dy2
    dx1 = -dx1 if x1 < 0 || x1 >= W
    dy1 = -dy1 if y1 < 0 || y1 >= H
    dx2 = -dx2 if x2 < 0 || x2 >= W
    dy2 = -dy2 if y2 < 0 || y2 >= H
    fb.line(x1, y1, x2, y2, PAL[(f * 24 + k * 3) % 256])
    trail << [x1, y1, x2, y2]
    if trail.size > 60
      o = trail.shift
      fb.line(o[0], o[1], o[2], o[3], 0)
    end
  end
end

# 4. color tunnel
fb.clear
scene_until(8000) do |f|
  30.times do |k|
    w = 20 + k * 20
    h = 15 + k * 15
    c = PAL[(k * 12 - f * 9) % 256]
    fb.rect(cx - w / 2, cy - h / 2, w, h, c)
    fb.rect(cx - w / 2 + 1, cy - h / 2 + 1, w - 2, h - 2, c)
  end
end

# 5. spirograph
fb.clear
curves = [[5, 3, 0], [7, 4, 40], [3, 2, 90], [9, 8, 140], [11, 7, 200]]
t0 = Machine.ms
curves.each_with_index do |c, n|
  a = c[0]
  b = c[1]
  px = nil
  py = 0
  i = 0
  while i <= 512 && Machine.ms - t0 < 9000
    x = cx + isin(i * a / 2) * 2 + icos(i * b / 2)
    y = cy + icos(i * a / 2) + isin(i * b / 2) / 2
    fb.line(px, py, x, y, PAL[(c[2] + i / 2) % 256]) if px
    px = x
    py = y
    i += 2
  end
end
Machine.vsync(30)

# 6. plasma (40 x 40 blocks)
fb.clear
scene_until(9000) do |f|
  12.times do |by|
    16.times do |bx|
      v = isin(bx * 16 + f * 7) + isin(by * 20 - f * 5) + isin((bx + by) * 12 + f * 3)
      fb.fill_rect(bx * 40, by * 40, 40, 40, PAL[(v / 3 + f * 4) % 256])
    end
  end
end

# 7. fireworks
fb.clear
parts = []
scene_until(10000) do |f|
  if f % 12 == 0
    x = 80 + rand(480)
    y = 60 + rand(200)
    c = rand(256)
    24.times do |k|
      s = 2 + rand(5)
      parts << [x * 16, y * 16, icos(k * 256 / 24) * s / 8, isin(k * 256 / 24) * s / 8, PAL[(c + k * 2) % 256], 40]
    end
  end
  alive = []
  parts.each do |p|
    fb.fill_rect(p[0] / 16, p[1] / 16, 3, 3, 0)
    p[0] += p[2]
    p[1] += p[3]
    p[3] += 3
    p[5] -= 1
    if p[5] > 0 && p[1] / 16 < H
      fb.fill_rect(p[0] / 16, p[1] / 16, 3, 3, p[4])
      alive << p
    end
  end
  parts = alive
end

# end
fb.clear
Machine.text_visible = true
puts "          --- end of demo ---"
