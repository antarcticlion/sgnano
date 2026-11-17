# Mexican hat: z = 100 cos(r) - 30 cos(3r), drawn with the classic hidden line method.
# Ported from samples/ruby/hat.rb (2026-10-30).
import math
M.mode = 2
fb = M.fb
fb.clear()
top = [480] * 640
d2r = 3.141592653589793 / 180.0
y = -180
while y <= 180:
    x = -180.0
    while x <= 180.0:
        r = d2r * (x * x + y * y) ** 0.5
        z = 100.0 * math.cos(r) - 30.0 * math.cos(3.0 * r)
        sx = int(320.0 + x * 1.2 + y * 0.5)
        sy = int(260.0 - y * 0.5 - z * 0.9)
        if 0 <= sx < 640 and sy < top[sx]:
            top[sx] = sy
            k = int((z + 130.0) * 255.0 / 260.0)
            fb.pset(sx, sy, M.rgb(k, 255 - k, 255))
        x += 0.5
    y += 6
print("done")
