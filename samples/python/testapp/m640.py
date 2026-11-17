# Mandelbrot set, 640 x 480, on the framebuffer (screen mode 2).
# Ported from samples/ruby/mandel640.rb (2026-10-30).
# The set is symmetric about the real axis: compute the upper half and mirror it.
M.mode = 2
fb = M.fb
fb.clear()
mx = 64
pal = []
for i in range(mx):
    t = i / mx
    u = 1.0 - t
    pal.append(M.rgb(int(9.0 * u * t * t * t * 255), int(15.0 * u * u * t * t * 255), int(8.5 * u * u * u * t * 255)))
pal.append(0)
w = 640
h = 480
x0 = -2.2
dx = 3.2 / w
y0 = -1.2
dy = 2.4 / h
for py in range(h // 2):
    ci = y0 + (py + 0.5) * dy
    ci2 = ci * ci
    for px in range(w):
        cr = x0 + px * dx
        q = (cr - 0.25) * (cr - 0.25) + ci2
        if q * (q + (cr - 0.25)) <= 0.25 * ci2 or (cr + 1.0) * (cr + 1.0) + ci2 <= 0.0625:
            n = mx
        else:
            zr = 0.0
            zi = 0.0
            n = 0
            while n < mx:
                zr2 = zr * zr
                zi2 = zi * zi
                if zr2 + zi2 > 4.0:
                    break
                zi = 2.0 * zr * zi + ci
                zr = zr2 - zi2 + cr
                n += 1
        c = pal[n]
        fb.pset(px, py, c)
        fb.pset(px, h - 1 - py, c)
print("done")
