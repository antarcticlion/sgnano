# Primitive drawing demo (2026-11-13, SPEC_gfx.md). The same pictures as apps/gfxdemo (SGX),
# samples/python/gfxdemo.py and samples/basic/gfxdemo.bas. Mode 2 (RGB555), three pages:
#   1 shapes and lines  2 paths and text  3 bitmaps.  Any key: next page, ESC: quit.
M = Machine
fb = M.fb
def c(r, g, b) = Machine.fb.rgb(r, g, b)

def next_page
  k = Machine.wait_key
  k != 0x1B
end

def title(fb, s)
  fb.font(M::FONT_ROM, 32, M::FW_BOLD).text_color(c(31, 31, 31)).bk(M::BK_TRANSPARENT)
  fb.text_out(16, 8, s)
  fb.font(M::FONT_ROM, 16).text_color(c(20, 20, 20), M::TA_RIGHT)
  fb.text_out(624, 456, "any key: next   ESC: quit")
end

def clear(fb)
  fb.reset_drawing
  fb.clear(c(2, 3, 6))
end

def page_shapes(fb)
  clear(fb); title(fb, "1. shapes and lines")
  hatch = [M::BS_HORIZONTAL, M::BS_VERTICAL, M::BS_FDIAGONAL, M::BS_BDIAGONAL, M::BS_CROSS, M::BS_DIAGCROSS]
  fb.bk(M::BK_OPAQUE, c(4, 4, 10))
  hatch.each_with_index do |h, i|
    fb.pen(c(31, 31, 31)).brush(c(31, 20, 5 * i), h)
    fb.rectangle(20 + i * 100, 60, 100 + i * 100, 120)
  end
  fb.bk(M::BK_TRANSPARENT)
  fb.pen(c(31, 31, 0), 3).brush(c(0, 12, 31)).round_rect(20, 140, 150, 230, 40, 40)
  fb.brush(c(31, 8, 8)).ellipse(170, 140, 300, 230)
  fb.brush(c(8, 28, 8)).pie(320, 130, 440, 240, 440, 185, 380, 130)
  fb.brush(c(28, 8, 28)).chord(460, 140, 620, 230, 620, 185, 460, 185)
  fb.pen(c(31, 31, 31)).brush(c(31, 24, 0))
  fb.fill_rule(M::FILL_NONZERO).polygon([80, 250, 104, 330, 30, 280, 130, 280, 56, 330])
  fb.fill_rule(M::FILL_EVENODD).polygon([230, 250, 254, 330, 180, 280, 280, 280, 206, 330])
  fb.fill_rule(M::FILL_NONZERO)
  [M::PS_SOLID, M::PS_DASH, M::PS_DOT, M::PS_DASHDOT, M::PS_DASHDOTDOT].each_with_index do |s, i|
    fb.pen(c(20, 31, 31), 1, s).move_to(320, 260 + i * 14).line_to(620, 260 + i * 14)
  end
  [[M::CAP_ROUND, M::JOIN_ROUND], [M::CAP_SQUARE, M::JOIN_BEVEL], [M::CAP_FLAT, M::JOIN_MITER]].each_with_index do |(cap, join), i|
    x = 330 + i * 100
    z = [x, 440, x + 40, 360, x + 80, 440]
    fb.pen(c(31, 16, 0), 14).pen_ext(cap, join).polyline(z)
    fb.pen(c(31, 31, 31)).polyline(z)
  end
  6.times do |i|
    fb.pen(c(31 - i * 5, i * 6, 31), 2).poly_bezier([20, 440, 80, 350 + i * 12, 200, 470 - i * 12, 290, 380])
  end
end

def star(fb, cx, cy, r, rot)
  fb.begin_path
  10.times do |i|
    a = rot + i * Math::PI / 5
    rr = i.odd? ? r * 0.45 : r
    x, y = cx + rr * Math.sin(a), cy - rr * Math.cos(a)
    i == 0 ? fb.path_move_to(x, y) : fb.path_line_to(x, y)
  end
  fb.close_path
end

def page_paths(fb)
  clear(fb); title(fb, "2. paths and text")
  # a TrueType-like glyph: quadratic outer ring and a hole in the other direction ("O")
  fb.brush(c(31, 22, 6)).pen(c(31, 31, 31), 2).aa(true)
  fb.begin_path.path_move_to(90, 60)
  fb.path_quad_to(160, 60, 160, 130).path_quad_to(160, 200, 90, 200).path_quad_to(20, 200, 20, 130).path_quad_to(20, 60, 90, 60).close_path
  fb.path_move_to(90, 95)
  fb.path_quad_to(60, 95, 60, 130).path_quad_to(60, 165, 90, 165).path_quad_to(120, 165, 120, 130).path_quad_to(120, 95, 90, 95).close_path
  fb.fill_stroke_path
  # stars turned by angle: left without anti-aliasing, right with it
  [false, true].each_with_index do |aa, side|
    fb.aa(aa)
    4.times do |i|
      fb.brush(c(8 + 6 * i, 16, 31 - 6 * i)).pen(0, 1, M::PS_NULL)
      star(fb, 230 + side * 200 + i * 40, 130, 50.0 - 9 * i, i * 0.3)
      fb.fill_path
    end
  end
  fb.aa(false).bk(M::BK_TRANSPARENT)
  x = 20
  [[M::FW_NORMAL, 0, "Normal"], [M::FW_BOLD, 0, "Bold"], [M::FW_NORMAL, M::FF_ITALIC, "Italic"],
   [M::FW_NORMAL, M::FF_UNDERLINE, "Underline"], [M::FW_NORMAL, M::FF_STRIKEOUT, "Strike"]].each do |w, f, s|
    fb.font(M::FONT_ROM, 24, w, f).text_color(c(31, 31, 20))
    fb.text_out(x, 230, s)
    x += fb.text_extent(s)[0] + 20
  end
  fb.font(M::FONT_ROM, 16, M::FW_NORMAL, 0, 900).text_color(c(20, 31, 20)).text_out(600, 440, "rotated 90")
  fb.font(M::FONT_ROM, 48, M::FW_BOLD).text_color(c(31, 16, 31)).text_out(20, 270, "描画 Draw")
  para = "DrawText wraps this paragraph inside the rectangle and centres every line. 日本語も字の境で折り返す。"
  fb.pen(c(12, 12, 20), 1, M::PS_DOT).brush(0, M::BS_NULL).rectangle(296, 266, 584, 444)
  fb.font(M::FONT_ROM, 16).text_color(c(31, 31, 31))
  fb.draw_text(para, 300, 270, 580, 440, M::DT_WORDBREAK | M::DT_CENTER)
end

def page_bitmaps(fb)
  clear(fb); title(fb, "3. bitmaps")
  im = M::Image.new(64, 64)
  key = im.rgb(31, 0, 31)                     # magenta is the transparent colour
  im.clear(key)
  im.pen(im.rgb(31, 31, 31), 2).brush(im.rgb(0, 20, 31)).ellipse(4, 4, 60, 60)
  im.brush(im.rgb(31, 31, 0)).polygon([16, 28, 36, 28, 36, 18, 50, 32, 36, 46, 36, 36, 16, 36])
  60.step(439, 20) { |y| 0.step(639, 20) { |x| fb.fill_rect(x, y, 20, 20, ((x + y) / 20).odd? ? c(6, 6, 10) : c(3, 3, 6)) } }   # mruby: Integer#step
  fb.bitblt(20, 80, 64, 64, im)
  fb.bitblt(100, 80, 64, 64, im, 0, 0, M::SRCCOPY, key)
  fb.stretch_blt(180, 80, 128, 128, im, 0, 0, 64, 64, M::SRCCOPY, key)
  fb.stretch_blt(452, 80, -128, 128, im, 0, 0, 64, 64, M::SRCCOPY, key)
  fb.stretch_blt(470, 208, 160, -128, im, 0, 0, 64, 64, M::SRCCOPY, key)
  fb.bitblt(20, 240, 64, 64, im, 0, 0, M::SRCINVERT)
  fb.bitblt(100, 240, 64, 64, im, 0, 0, M::NOTSRCCOPY)
  8.times { |i| s = 16 + i * 6; fb.stretch_blt(20 + i * 70, 330, s, s, im, 0, 0, 64, 64, M::SRCCOPY, key) }
  dib = (0...32).map { |i| [i * 8, 255 - i * 8, 128 + i * 4].pack("C3") }.join
  fb.draw_dib(200, 240, 400, 60, dib, M::DIB_RGB888, 32, 1)
  im.free
end

M.mode = 2
M.text_visible = false
page_shapes(fb)
if next_page
  page_paths(fb)
  if next_page
    page_bitmaps(fb)
    next_page
  end
end
M.text_visible = true
M.mode = 1
