# Mandelbrot set in text (79 x 24)
chars = " .,:-=+*%#"
iter = 40
h = 24
w = 79
h.times do |y|
  ci = (y - h / 2) * 2.4 / h
  line = ""
  w.times do |x|
    cr = (x - w * 0.65) * 3.2 / w
    zr = 0.0
    zi = 0.0
    n = 0
    while n < iter && zr * zr + zi * zi < 4.0
      t = zr * zr - zi * zi + cr
      zi = 2.0 * zr * zi + ci
      zr = t
      n += 1
    end
    line << (n == iter ? "@" : chars[n % chars.size])
  end
  puts line
end
