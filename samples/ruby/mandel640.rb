# Mandelbrot set, 640 x 480, on the framebuffer (screen mode 2).
# The set is symmetric about the real axis: compute the upper half and mirror it.
# Points inside the main cardioid and the period-2 bulb are skipped (they never escape).
Machine.mode = 2
fb = Machine.fb
fb.clear
max = 64
pal = []
max.times do |i|
  t = i.to_f / max
  u = 1.0 - t
  pal << Machine.rgb((9.0 * u * t * t * t * 255).to_i, (15.0 * u * u * t * t * 255).to_i, (8.5 * u * u * u * t * 255).to_i)
end
pal << 0
w = 640
h = 480
x0 = -2.2
dx = 3.2 / w
y0 = -1.2
dy = 2.4 / h
t0 = Time.now rescue nil
(h / 2).times do |py|
  ci = y0 + (py + 0.5) * dy
  ci2 = ci * ci
  w.times do |px|
    cr = x0 + px * dx
    q = (cr - 0.25) * (cr - 0.25) + ci2
    if q * (q + (cr - 0.25)) <= 0.25 * ci2 || (cr + 1.0) * (cr + 1.0) + ci2 <= 0.0625
      n = max
    else
      zr = 0.0
      zi = 0.0
      n = 0
      while n < max
        zr2 = zr * zr
        zi2 = zi * zi
        break if zr2 + zi2 > 4.0
        zi = 2.0 * zr * zi + ci
        zr = zr2 - zi2 + cr
        n += 1
      end
    end
    c = pal[n]
    fb.pset(px, py, c)
    fb.pset(px, h - 1 - py, c)
  end
end
puts "done"
