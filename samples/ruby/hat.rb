# Mexican hat: z = 100 cos(r) - 30 cos(3r), drawn with the classic hidden line method
# (front to back; a point is drawn only when it is above everything drawn in its column).
Machine.mode = 2
fb = Machine.fb
fb.clear
top = Array.new(640, 480)
d2r = Math::PI / 180.0
y = -180
while y <= 180
  x = -180.0
  while x <= 180.0
    r = d2r * Math.sqrt(x * x + y * y)
    z = 100.0 * Math.cos(r) - 30.0 * Math.cos(3.0 * r)
    sx = (320.0 + x * 1.2 + y * 0.5).to_i
    sy = (260.0 - y * 0.5 - z * 0.9).to_i
    if sx >= 0 && sx < 640 && sy < top[sx]
      top[sx] = sy
      k = ((z + 130.0) * 255.0 / 260.0).to_i
      fb.pset(sx, sy, Machine.rgb(k, 255 - k, 255))
    end
    x += 0.5
  end
  y += 6
end
puts "done"
