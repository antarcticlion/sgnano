# FrameBuffer: triangles and block transfer (2026-10-16). Checks the pixels with pget, then draws a small scene.
$ng = 0
def check(name, cond)
  puts "#{cond ? 'ok' : 'NG'} #{name}"
  $ng += 1 unless cond
end
Machine.mode = 2
fb = Machine.fb
red, green, blue, white = Machine.rgb(255, 0, 0), Machine.rgb(0, 255, 0), Machine.rgb(0, 0, 255), Machine.rgb(255, 255, 255)
fb.clear

# --- triangles ---
fb.fill_triangle(100, 10, 10, 110, 190, 110, red)
check "fill_triangle inside", fb.pget(100, 80) == red
check "fill_triangle vertices", fb.pget(100, 10) == red && fb.pget(10, 110) == red && fb.pget(190, 110) == red
check "fill_triangle outside", fb.pget(20, 20) == 0 && fb.pget(100, 111) == 0
fb.triangle(300, 10, 210, 110, 390, 110, green)
check "triangle edge", fb.pget(300, 10) == green && fb.pget(300, 110) == green
check "triangle hollow", fb.pget(300, 80) == 0
fb.fill_triangle(400, 50, 450, 50, 500, 50, blue)            # flat: one row
check "flat triangle", fb.pget(450, 50) == blue && fb.pget(450, 49) == 0
fb.fill_triangle(-50, 470, 30, 400, 30, 600, blue)           # partly outside the screen
check "clipped triangle", fb.pget(20, 470) == blue

# --- blit ---
fb.fill_rect(10, 200, 40, 30, white)
fb.pset(10, 200, red)
fb.blit(10, 200, 40, 30, 100, 210)                           # copy on the write page
check "blit copy", fb.pget(100, 210) == red && fb.pget(139, 239) == white && fb.pget(140, 210) == 0
fb.blit(100, 210, 40, 30, 110, 215)                          # overlapping move (down and right)
check "blit overlap", fb.pget(110, 215) == red && fb.pget(149, 244) == white
fb.blit(110, 215, 40, 30, 105, 212)                          # overlapping move (up and left)
check "blit overlap back", fb.pget(105, 212) == red
fb.blit(10, 200, 40, 30, 620, 470)                           # clipped at the edges
check "blit clipped", fb.pget(620, 470) == red && fb.pget(639, 479) == white
fb.blit(-5, 195, 20, 10, 200, 200)                           # source partly outside
check "blit source clipped", fb.pget(215, 205) == red && fb.pget(200, 205) == 0
# from another page, with a transparent color
Machine.write_page = 1
fb.clear(blue)
fb.fill_rect(0, 0, 20, 20, green)
Machine.write_page = 0
fb.blit(0, 0, 30, 30, 300, 300, 1)                           # page 1 -> page 0
check "blit from page 1", fb.pget(300, 300) == green && fb.pget(325, 325) == blue
fb.fill_rect(400, 300, 30, 30, white)
fb.blit(0, 0, 30, 30, 400, 300, 1, blue)                      # blue is transparent
check "blit transparent", fb.pget(400, 300) == green && fb.pget(425, 325) == white
begin
  fb.blit(0, 0, 10, 10, 0, 0, 9)
  check "bad page refused", false
rescue ArgumentError
  check "bad page refused", true
end

# --- get_block / put_block ---
b = fb.get_block(10, 200, 40, 30)
check "get_block size", b.bytesize == 40 * 30 * 2
check "get_block pixel", b.getbyte(0) | (b.getbyte(1) << 8) == red
fb.put_block(500, 100, 40, 30, b)
check "put_block", fb.pget(500, 100) == red && fb.pget(539, 129) == white
fb.fill_rect(500, 150, 40, 30, green)
fb.put_block(500, 150, 40, 30, b, white)                     # white is transparent
check "put_block transparent", fb.pget(500, 150) == red && fb.pget(520, 170) == green
e = fb.get_block(630, 470, 20, 20)                           # partly outside: zeros
check "get_block outside", e.getbyte(e.bytesize - 1) == 0 && (e.getbyte(0) | (e.getbyte(1) << 8)) == white
begin
  fb.put_block(0, 0, 10, 10, "short")
  check "short string refused", false
rescue ArgumentError
  check "short string refused", true
end

# --- a small scene: a ship made of triangles, copied around with blit ---
fb.clear
fb.fill_triangle(20, 0, 0, 30, 40, 30, Machine.rgb(255, 200, 0))
fb.fill_triangle(20, 8, 10, 26, 30, 26, Machine.rgb(255, 60, 0))
t0 = Machine.ms
100.times { |i| fb.blit(0, 0, 41, 31, 60 + (i % 10) * 56, 60 + (i / 10) * 40) }
puts "100 blits of 41x31 in #{Machine.ms - t0} ms"
puts $ng == 0 ? "all ok" : "#{$ng} NG"
