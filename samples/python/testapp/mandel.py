# Mandelbrot set in text (79 x 24).  Ported from samples/ruby/mandel.rb (2026-10-30).
chars = " .,:-=+*%#"
iter = 40
h = 24
w = 79
for y in range(h):
    ci = (y - h // 2) * 2.4 / h
    line = ""
    for x in range(w):
        cr = (x - w * 0.65) * 3.2 / w
        zr = 0.0
        zi = 0.0
        n = 0
        while n < iter and zr * zr + zi * zi < 4.0:
            t = zr * zr - zi * zi + cr
            zi = 2.0 * zr * zi + ci
            zr = t
            n += 1
        line += "@" if n == iter else chars[n % len(chars)]
    print(line)
