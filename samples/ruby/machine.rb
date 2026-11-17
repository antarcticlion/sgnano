# Machine / Machine::FrameBuffer: exercises every method and checks the pixels with pget.
$ng = 0
def check(name, cond)
  puts "#{cond ? 'ok' : 'NG'} #{name}"
  $ng += 1 unless cond
end
puts "mode #{Machine.mode}"
Machine.mode = 2
check "mode = 2", Machine.mode == 2
check "fb is shown in mode 2", Machine.fb_visible?
Machine.fb_visible = false
check "fb_visible = false", !Machine.fb_visible?
Machine.fb_visible = true
check "fb_visible = true", Machine.fb_visible?
Machine.text_visible = false
check "text_visible = false", !Machine.text_visible?
Machine.text_visible = true
check "text_visible = true", Machine.text_visible?
begin
  Machine.mode = 8
  check "mode 8 refused", false
rescue ArgumentError
  check "mode 8 refused", true
end
Machine.vsync
Machine.vsync(2)
fb = Machine.fb
check "width x height", fb.width == 640 && fb.height == 480
check "FrameBuffer.new", Machine::FrameBuffer.new.width == 640
red = Machine.rgb(255, 0, 0)
green = Machine.rgb(0, 255, 0)
blue = Machine.rgb(0, 0, 255)
white = Machine.rgb(255, 255, 255)
check "rgb gives different colors", red != green && green != blue && white != 0
check "rgb clamps", Machine.rgb(300, -5, 255) == Machine.rgb(255, 0, 255)
fb.clear(blue)
check "clear(color)", fb.pget(0, 0) == blue && fb.pget(639, 479) == blue
fb.clear
check "clear", fb.pget(320, 240) == 0
fb.pset(10, 10, red)
check "pset / pget", fb.pget(10, 10) == red
fb.pset(12.7, 10.2, green)
check "float coordinates", fb.pget(12, 10) == green
fb.pset(-1, 5, red)
fb.pset(640, 5, red)
check "outside is not drawn", fb.pget(-1, 5).nil? && fb.pget(640, 5).nil? && fb.pget(0, 5) == 0
fb.line(20, 20, 29, 29, white)
ok = true
10.times { |i| ok = false unless fb.pget(20 + i, 20 + i) == white }
check "diagonal line", ok && fb.pget(21, 20) == 0
fb.line(40, 20, 49, 20, white)
check "horizontal line", fb.pget(40, 20) == white && fb.pget(49, 20) == white && fb.pget(50, 20) == 0
fb.line(60, 29, 60, 20, white)
check "vertical line upward", fb.pget(60, 20) == white && fb.pget(60, 29) == white && fb.pget(60, 30) == 0
fb.line(-100, 100, 700, 100, green)
check "clipped line", fb.pget(0, 100) == green && fb.pget(639, 100) == green
fb.line(0, 479, 639, 0, red)
check "long diagonal", fb.pget(0, 479) == red && fb.pget(639, 0) == red
fb.rect(100, 120, 10, 5, red)
check "rect corners", fb.pget(100, 120) == red && fb.pget(109, 120) == red && fb.pget(100, 124) == red && fb.pget(109, 124) == red
check "rect is hollow", fb.pget(105, 122) == 0 && fb.pget(110, 120) == 0
fb.fill_rect(120, 120, 4, 3, blue)
n = 0
(118..125).each { |x| (118..124).each { |y| n += 1 if fb.pget(x, y) == blue } }
check "fill_rect fills 4 x 3", n == 12
fb.fill_rect(630, 470, 50, 50, white)
check "clipped fill_rect", fb.pget(639, 479) == white && fb.pget(629, 479) == 0
fb.rect(300, 300, 0, 5, red)
fb.fill_rect(305, 300, -3, 4, red)
check "empty rects draw nothing", fb.pget(300, 300) == 0 && fb.pget(304, 300) == 0
begin
  fb.pset(1, 2)
  check "missing argument refused", false
rescue ArgumentError
  check "missing argument refused", true
end
begin
  fb.line(0, 0, "a", 1, red)
  check "wrong type refused", false
rescue TypeError
  check "wrong type refused", true
end
# framebuffer pages: display and write pages are chosen separately (double buffering)
check "pages", Machine.pages == 4
Machine.write_page = 1
check "write_page = 1", Machine.write_page == 1
fb.clear(red)
Machine.write_page = 0
check "pages are separate", fb.pget(5, 5) != red
Machine.write_page = 1
check "page 1 kept its contents", fb.pget(5, 5) == red
Machine.display_page = 1
check "display_page = 1", Machine.display_page == 1
Machine.display_page = 0
Machine.write_page = 0
check "back to page 0", Machine.display_page == 0 && Machine.write_page == 0
begin
  Machine.write_page = 4
  check "page 4 refused", false
rescue ArgumentError
  check "page 4 refused", true
end
# a small picture to look at
fb.clear
8.times { |i| fb.rect(200 + i * 10, 150 + i * 10, 240 - i * 20, 180 - i * 20, Machine.rgb(255 - i * 30, i * 30, 128)) }
32.times { |i| fb.line(320, 240, i * 20, 470, Machine.rgb(i * 8, 255 - i * 8, 255)) }
fb.fill_rect(10, 10, 100, 60, Machine.rgb(255, 200, 0))
puts $ng == 0 ? "all ok" : "#{$ng} NG"
