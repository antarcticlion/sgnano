# NEON CIRCUIT - POLYGON EDITION (precomputed playback)
# Target: sgnano / mruby 4.0. Put this .RB and NEON_CIRCUIT_POLY.DAT in the same folder.
# The host generator (generate_neon_circuit_polygon.py) projects, lights, fogs, clips and
# sorts the scene; each frame is a list of flat-shaded triangles in painter's order
# (far to near) plus neon edge lines. Playback draws them with fill_triangle and line.
# Title cards, HUD panels, digits and the sunset sun are drawn once into spare
# framebuffer pages (the "atlas", pages 2 and 3) and copied every frame with blit.

$nc_log_path = "NEON_POLY.LOG"
$nc_log_failed = false
$nc_stage = "BOOT"

def nc_log(tag, message)
  return if $nc_log_failed
  line = Machine.ms.to_i.to_s + "ms [" + tag + "] " + message
  begin
    File.open($nc_log_path, "a") { |f| f.write(line + "\n") }
  rescue => e
    $nc_log_failed = true
    Machine.text_visible = true
    puts "LOG ERROR: " + e.message.to_s
  end
end

begin
  File.write($nc_log_path, "NEON CIRCUIT POLYGON EDITION LOG\n")
rescue => e
  $nc_log_failed = true
end

C_BLACK   = Machine.rgb(0, 0, 0)
C_DARK    = Machine.rgb(2, 3, 14)
C_BLUE    = Machine.rgb(20, 35, 255)
C_CYAN    = Machine.rgb(0, 235, 255)
C_WHITE   = Machine.rgb(255, 255, 255)
C_HOTPINK = Machine.rgb(255, 45, 190)
C_PURPLE  = Machine.rgb(145, 55, 255)
C_LIME    = Machine.rgb(100, 255, 90)
C_AMBER   = Machine.rgb(255, 185, 25)
C_GROUND  = Machine.rgb(6, 0, 14)
C_KEY     = Machine.rgb(248, 0, 248)     # transparent color of the atlas (not used by the scene)
SKY = [Machine.rgb(20, 4, 60), Machine.rgb(38, 7, 68), Machine.rgb(56, 10, 76),
       Machine.rgb(74, 13, 84), Machine.rgb(92, 16, 92), Machine.rgb(110, 19, 100)]

ATLAS_A = 2     # page: title card, finish card, sun, HUD panels
ATLAS_B = 3     # page: grid card, big digits, small font, labels

FONT = {
  "A" => ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
  "B" => ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
  "C" => ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
  "D" => ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
  "E" => ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
  "F" => ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
  "G" => ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
  "H" => ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
  "I" => ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
  "K" => ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
  "L" => ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
  "M" => ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
  "N" => ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
  "O" => ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
  "P" => ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
  "R" => ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
  "S" => ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
  "T" => ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
  "U" => ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
  "V" => ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
  "W" => ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
  "X" => ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
  "Y" => ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
  "-" => ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
  ":" => ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
  "." => ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
  "0" => ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
  "1" => ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
  "2" => ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
  "3" => ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
  "4" => ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
  "5" => ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
  "6" => ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
  "7" => ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
  "8" => ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
  "9" => ["01110", "10001", "10001", "01111", "00001", "00001", "01110"]
}

# ---- drawing used only while building the atlas (slow: many fill_rect calls) ----
def draw_text(fb, text, x, y, scale, color)
  cursor = x
  text.each_char do |ch|
    glyph = FONT[ch]
    if glyph
      row = 0
      while row < 7
        bits = glyph[row]
        col = 0
        while col < 5
          if bits.getbyte(col) == 49
            finish = col + 1
            finish += 1 while finish < 5 && bits.getbyte(finish) == 49
            fb.fill_rect(cursor + col * scale, y + row * scale, (finish - col) * scale, scale, color)
            col = finish
          else
            col += 1
          end
        end
        row += 1
      end
    end
    cursor += (ch == " " ? 4 : 6) * scale
  end
end

def draw_text_outline(fb, text, x, y, scale, color, outline)
  [[-2, 0], [2, 0], [0, -2], [0, 2], [-2, -2], [2, -2], [-2, 2], [2, 2]].each do |d|
    draw_text(fb, text, x + d[0], y + d[1], scale, outline)
  end
  draw_text(fb, text, x, y, scale, color)
end

def draw_ellipse(fb, cx, cy, rx, ry, color, segments)
  lx = cx + rx
  ly = cy
  i = 1
  while i <= segments
    a = 2.0 * Math::PI * i / segments
    x = cx + Math.cos(a) * rx
    y = cy + Math.sin(a) * ry
    fb.line(lx, ly, x, y, color)
    lx = x
    ly = y
    i += 1
  end
end

# A neon "card": filled panel, ellipses, two frames. Drawn at (ox, oy) in the atlas.
def draw_card(fb, ox, oy, w, h, outer, inner, ellipses)
  fb.fill_rect(ox, oy, w, h, C_BLACK)
  if ellipses
    draw_ellipse(fb, ox + w / 2, oy + h / 2 - 2, 224, 70, C_BLUE, 32)
    draw_ellipse(fb, ox + w / 2, oy + h / 2 - 2, 184, 52, C_PURPLE, 32)
  end
  fb.rect(ox, oy, w, h, outer)
  fb.rect(ox + 12, oy + 12, w - 24, h - 24, inner)
end

# Synthwave sun: a half disk, amber at the top to pink at the horizon, with gaps that widen
# toward the horizon. One fill_rect a row; drawn once into the atlas, then blitted.
SUN = [Machine.rgb(255, 210, 60), Machine.rgb(255, 160, 50), Machine.rgb(255, 105, 90), Machine.rgb(255, 60, 150)]
def draw_sun(fb, ox, oy)
  r = 60
  y = 0
  while y < 64
    dy = 63 - y
    if dy <= r
      gap = dy < 28 && (dy % 7) < (4 - dy / 7)
      unless gap
        hw = Math.sqrt((r * r - dy * dy).to_f).to_i
        fb.fill_rect(ox + 64 - hw, oy + y, hw * 2, 1, SUN[y * 4 / 64])
      end
    end
    y += 1
  end
end

def font_x(ch)
  SMALL_CHARS.index(ch) * 12
end
SMALL_CHARS = "0123456789:.-"
LABELS = ["CITY CANYON", "OVERTAKE", "HIGH SPEED", "FINAL RUN", "LAP"]

def build_atlas(fb)
  Machine.write_page = ATLAS_A
  fb.clear(C_KEY)
  # title card (516x190) at (0, 0)
  draw_card(fb, 0, 0, 516, 190, C_CYAN, C_BLUE, true)
  draw_text_outline(fb, "NEON CIRCUIT", 114, 39, 4, C_WHITE, C_BLACK)
  draw_text_outline(fb, "POLYGON RACE", 152, 98, 2, C_CYAN, C_BLACK)
  # finish card (520x188) at (0, 192)
  draw_card(fb, 0, 192, 520, 188, C_CYAN, C_HOTPINK, true)
  draw_text_outline(fb, "RACE COMPLETE", 125, 226, 3, C_WHITE, C_BLACK)
  draw_text_outline(fb, "CHECKERED FLAG", 125, 278, 2, C_CYAN, C_BLACK)
  draw_text(fb, "NEON CIRCUIT", 174, 336, 2, C_LIME)
  # sun (128x64) at (520, 0)
  draw_sun(fb, 520, 0)
  # HUD panels (150x25) at (520, 70) and (520, 100)
  fb.fill_rect(520, 70, 150, 25, C_BLACK)
  fb.rect(520, 70, 150, 25, C_CYAN)
  fb.fill_rect(524, 75, 104, 5, C_DARK)
  fb.fill_rect(524, 85, 138, 4, C_DARK)
  fb.fill_rect(520, 100, 150, 25, C_BLACK)
  fb.rect(520, 100, 150, 25, C_BLUE)
  fb.fill_rect(526, 105, 138, 5, C_DARK)
  fb.fill_rect(526, 115, 138, 4, C_DARK)

  Machine.write_page = ATLAS_B
  fb.clear(C_KEY)
  # grid card (396x160) at (0, 0)
  fb.fill_rect(0, 0, 396, 160, C_BLACK)
  fb.rect(0, 0, 396, 160, C_HOTPINK)
  fb.rect(10, 10, 376, 140, C_CYAN)
  draw_text_outline(fb, "GRID READY", 96, 27, 3, C_WHITE, C_BLACK)
  # big digits 1..3 (29x39 each, with outline) at (400 + 32 * i, 0)
  3.times { |i| draw_text_outline(fb, (i + 1).to_s, 402 + 32 * i, 2, 5, C_LIME, C_BLACK) }
  # subtitle at (0, 170), 324x14, transparent background
  draw_text(fb, "MEGACITY HIGHWAY GRAND PRIX", 0, 170, 2, C_LIME)
  # small font strip at (0, 200): 12 px a character, 10x14 glyphs
  SMALL_CHARS.each_char { |ch| draw_text(fb, ch, font_x(ch), 200, 2, C_WHITE) }
  # labels at (0, 220 + 16 * i)
  LABELS.each_with_index { |s, i| draw_text(fb, s, 0, 220 + 16 * i, 2, C_CYAN) }
end

# ---- per frame ----
def blit_text(fb, s, x, y)
  s.each_char do |ch|
    fb.blit(font_x(ch), 200, 10, 14, x, y, ATLAS_B, C_KEY)
    x += 12
  end
end

def draw_background(fb, hy, sun_x)
  if hy <= 0
    fb.fill_rect(0, 0, 640, 480, C_GROUND)
    return
  end
  top = hy > 480 ? 480 : hy
  b = 0
  while b < 6
    y0 = top * b / 6
    y1 = top * (b + 1) / 6
    fb.fill_rect(0, y0, 640, y1 - y0, SKY[b])
    b += 1
  end
  fb.blit(520, 0, 128, 64, sun_x - 64, hy - 64, ATLAS_A, C_KEY) if hy < 544
  fb.fill_rect(0, hy, 640, 480 - hy, C_GROUND) if hy < 480
end

def draw_frame(fb, a)
  nt = a[0]
  nl = a[1]
  draw_background(fb, a[2], a[3])
  j = 4
  k = 0
  while k < nt
    fb.fill_triangle(a[j], a[j + 1], a[j + 2], a[j + 3], a[j + 4], a[j + 5], PAL[a[j + 6]])
    j += 7
    k += 1
  end
  k = 0
  while k < nl
    fb.line(a[j], a[j + 1], a[j + 2], a[j + 3], PAL[a[j + 4]])
    j += 5
    k += 1
  end
end

def draw_hud(fb, elapsed, frame)
  pulse = (frame * 7) % 104
  fb.blit(520, 70, 150, 25, 12, 10, ATLAS_A)
  fb.fill_rect(16, 15, pulse, 5, C_LIME)
  fb.fill_rect(16, 25, (frame * 3) % 138, 4, C_HOTPINK)
  fb.blit(520, 100, 150, 25, 478, 10, ATLAS_A)
  fb.fill_rect(484, 15, 138 - pulse, 5, C_CYAN)
  fb.fill_rect(484, 25, (frame * 11) % 138, 4, C_PURPLE)
  # race clock (sprite font) and section label
  race = elapsed - 4.2
  race = 0.0 if race < 0
  tenths = (race * 10).to_i
  clock = format("%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
  fb.blit(0, 220 + 16 * 4, 34, 14, 16, 42, ATLAS_B, C_KEY)          # "LAP"
  blit_text(fb, clock, 56, 42)
  li = 0
  li = 1 if race >= 7.0
  li = 2 if race >= 20.0
  li = 3 if race >= 36.0
  w = LABELS[li].length * 12 - 2
  fb.blit(0, 220 + 16 * li, w, 14, 624 - w, 42, ATLAS_B, C_KEY)
  fb.line(12, 405, 12, 420, C_BLUE)
  fb.line(12, 420, 27, 420, C_BLUE)
  fb.line(628, 405, 628, 420, C_BLUE)
  fb.line(613, 420, 628, 420, C_BLUE)
end

def draw_cards(fb, elapsed)
  if elapsed < 2.8
    fb.blit(0, 0, 516, 190, 62, 126, ATLAS_A)
    fb.blit(0, 170, 324, 14, 158, 350, ATLAS_B, C_KEY)
  elsif elapsed < 4.2
    fb.blit(0, 0, 396, 160, 122, 150, ATLAS_B)
    n = (4.2 - elapsed).to_i + 1
    n = 1 if n < 1
    n = 3 if n > 3
    fb.blit(400 + 32 * (n - 1), 0, 31, 41, 305, 222, ATLAS_B, C_KEY)
  elsif elapsed >= 45.5
    fb.blit(0, 192, 520, 188, 60, 132, ATLAS_A)
  end
end

def present
  Machine.display_page = $back
  $front, $back = $back, $front
  Machine.write_page = $back
end

# ---- the frame pack ----
def open_pack(path)
  f = File.open(path, "rb")
  h = f.read(10)
  raise "short header" if h.nil? || h.bytesize != 10
  raise "not an NCP1 pack" if h[0, 4] != "NCP1"
  v = h[4, 6].unpack("S<CCS<")
  frames = v[0]
  fps = v[1]
  npal = v[3]
  pb = f.read(npal * 3).bytes
  pal = Array.new(npal) { |i| Machine.rgb(pb[i * 3], pb[i * 3 + 1], pb[i * 3 + 2]) }
  offs = f.read(frames * 4).unpack("L<*")
  offs << File.size(path)
  [f, frames, fps, pal, offs]
end

def read_frame(f, offs, i)
  f.seek(offs[i], 0)
  n = offs[i + 1] - offs[i]
  data = f.read(n)
  raise "short frame " + i.to_s if data.nil? || data.bytesize != n
  data.unpack("s<*")
end

$pack = nil
begin
  $nc_stage = "MODE"
  Machine.mode = 2
  Machine.text_visible = false
  fb = Machine.fb
  raise "needs 4 framebuffer pages" if Machine.pages < 4
  [0, 1].each { |p| Machine.write_page = p; fb.clear(C_BLACK) }
  $front = 0
  $back = 1
  Machine.display_page = 0
  Machine.write_page = 1
  # loading card, drawn directly
  draw_card(fb, 74, 150, 492, 180, C_CYAN, C_BLUE, false)
  draw_text_outline(fb, "NEON CIRCUIT", 176, 183, 4, C_WHITE, C_BLACK)
  draw_text_outline(fb, "BUILDING SPRITES", 224, 240, 2, C_CYAN, C_BLACK)
  present
  t = Machine.ms
  $nc_stage = "ATLAS"
  build_atlas(fb)
  Machine.write_page = $back
  nc_log("ATLAS", "built in " + (Machine.ms - t).to_s + "ms")

  $nc_stage = "OPEN PACK"
  pk = open_pack("NEON_CIRCUIT_POLY.DAT")
  $pack = pk[0]
  frame_count = pk[1]
  fps = pk[2]
  PAL = pk[3]
  offs = pk[4]
  nc_log("PACK", "frames=" + frame_count.to_s + " fps=" + fps.to_s + " palette=" + PAL.size.to_s)

  $nc_stage = "FIRST FRAME"
  draw_frame(fb, read_frame($pack, offs, 0))
  draw_hud(fb, 0.0, 0)
  draw_cards(fb, 0.0)
  present
  start = Machine.ms
  nc_log("PLAYBACK_START", "duration=50s")

  $nc_stage = "PLAYBACK"
  last = 0
  shown = 1
  skipped = 0
  checkpoint = 0
  render_ms = 0
  worst_ms = 0
  while true
    el = Machine.ms - start
    break if el >= 50000
    target = el * fps / 1000
    target = frame_count - 1 if target >= frame_count
    if target > last
      skipped += target - last - 1
      elapsed = target.to_f / fps
      t = Machine.ms
      draw_frame(fb, read_frame($pack, offs, target))
      draw_hud(fb, elapsed, target)
      draw_cards(fb, elapsed)
      present
      render_ms = Machine.ms - t
      worst_ms = render_ms if render_ms > worst_ms
      last = target
      shown += 1
    else
      Machine.vsync          # wait one display frame (about 17 ms)
    end
    c = (Machine.ms - start) / 5000
    if c > checkpoint
      checkpoint = c
      nc_log("PROGRESS", "elapsed=" + (Machine.ms - start).to_s + "ms shown=" + shown.to_s + " skipped=" + skipped.to_s +
             " frame=" + last.to_s + " render_ms=" + render_ms.to_s + " worst_ms=" + worst_ms.to_s)
    end
  end
  nc_log("DONE", "shown=" + shown.to_s + " skipped=" + skipped.to_s + " worst_ms=" + worst_ms.to_s)
  $pack.close
  $pack = nil
rescue => e
  begin
    $pack.close if $pack
  rescue => e2
  end
  Machine.text_visible = true
  nc_log("ERROR", "stage=" + $nc_stage + " " + e.class.to_s + ": " + e.message.to_s)
  puts "NEON CIRCUIT ERROR"
  puts "STAGE: " + $nc_stage
  puts e.class.to_s + ": " + e.message.to_s
end
