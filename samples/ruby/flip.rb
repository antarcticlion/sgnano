# Double buffering: draw on the hidden page, then show it (no flicker). Runs for 15 seconds.
Machine.mode = 2
Machine.text_visible = false
fb = Machine.fb
2.times do |pg|
  Machine.write_page = pg
  fb.clear
end
n = 12
xs = Array.new(n, 0)
ys = Array.new(n, 0)
dx = Array.new(n, 0)
dy = Array.new(n, 0)
cs = Array.new(n, 0)
n.times do |i|
  xs[i] = rand(560)
  ys[i] = rand(400)
  dx[i] = 3 + rand(6)
  dy[i] = 3 + rand(6)
  cs[i] = Machine.rgb(80 + rand(176), 80 + rand(176), 80 + rand(176))
end
old = [[], []]          # boxes drawn on each page (to erase them two frames later)
show = 0
frames = 0
t0 = Machine.ms
while Machine.ms - t0 < 15000
  back = 1 - show
  Machine.write_page = back
  old[back].each { |b| fb.fill_rect(b[0], b[1], 80, 80, 0) }
  old[back] = []
  n.times do |i|
    xs[i] += dx[i]
    ys[i] += dy[i]
    dx[i] = -dx[i] if xs[i] < 0 || xs[i] > 560
    dy[i] = -dy[i] if ys[i] < 0 || ys[i] > 400
    fb.fill_rect(xs[i], ys[i], 80, 80, cs[i])
    fb.rect(xs[i], ys[i], 80, 80, Machine.rgb(255, 255, 255))
    old[back] << [xs[i], ys[i]]
  end
  Machine.display_page = back
  show = back
  frames += 1
end
Machine.display_page = 0
Machine.write_page = 0
Machine.text_visible = true
puts "#{frames} frames in 15 s"
