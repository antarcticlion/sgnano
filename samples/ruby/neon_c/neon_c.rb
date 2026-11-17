# NEON CIRCUIT - POLYGON EDITION (sgnano, CLUT8 playback, gfx edition 2026-11-15)
# Put this .RB and the .DAT in the same folder. The 8 fps pack (NEON_CIRCUIT_POLY_8.DAT)
# is used when present; otherwise the original 4 fps pack (NEON_CIRCUIT_POLY.DAT).
# The host generator (generate_neon_circuit_polygon.py) projects, lights, fogs, clips and
# sorts the scene; each frame is a list of flat-shaded triangles in painter's order
# (far to near) plus neon edge lines.
#
# 2026-11-15: redrawn with the primitive drawing of the firmware (SPEC_gfx.md):
# - cards: rounded neon frames (wide dim pens under a thin bright one), ellipse rings,
#   ROM-font titles with a glow and an outline (font / text_out / TA_CENTER)
# - the sunset sun: one ellipse per colour band through the clip rectangle
# - HUD: rounded panels, the race clock and the section name as text, a speed gauge (angle_arc)
# - the neon edge lines of the scene 2 pixels thick
# The wide pens are used only for what is drawn once (the atlas): every frame keeps to the cheap
# calls (fill_triangle, 1-pixel line / arc, text_out, blit). Measured on the device: a 2-pixel pen
# line 1.29 ms against 0.10 ms, a 5-pixel arc 3.8 ms against 0.27 ms.
# Cards, panels, the gauge face and the sun are drawn once into spare framebuffer pages (the "atlas",
# pages 2 and 3) and copied every frame with blit.
# q / ESC ends. Progress goes to the UART log (puts); no file is written during playback.

$nc_stage = "BOOT"
M = Machine

def nc_log(tag, message)
  puts "NEON [" + tag + "] " + message
end

# CLUT8 palette indices (mode 3). 0..191 are the pack palette (scene); 192.. are the
# fixed UI colours. The 8 fps pack has 163 colours, so UI_BASE must stay above that.
# 255 is the transparent key used by the atlas pages.
UI_BASE   = 192
C_BLACK   = 192
C_DARK    = 193
C_BLUE    = 194
C_CYAN    = 195
C_WHITE   = 196
C_HOTPINK = 197
C_PURPLE  = 198
C_LIME    = 199
C_AMBER   = 200
C_GROUND  = 201
SKY = [202, 203, 204, 205, 206, 207]
SUN = [208, 209, 210, 211]
# glow shades (dim versions of the neon colours, for the wide pens under the bright line)
G_CYAN    = 212
G_PINK    = 213
G_BLUE    = 214
G_PURPLE  = 215
G_LIME    = 216
C_PANEL   = 217
C_KEY = 255

def set_fixed_palette
  [[C_BLACK,0,0,0],[C_DARK,2,3,14],[C_BLUE,20,35,255],[C_CYAN,0,235,255],
   [C_WHITE,255,255,255],[C_HOTPINK,255,45,190],[C_PURPLE,145,55,255],
   [C_LIME,100,255,90],[C_AMBER,255,185,25],[C_GROUND,6,0,14],
   [202,20,4,60],[203,38,7,68],[204,56,10,76],[205,74,13,84],[206,92,16,92],[207,110,19,100],
   [208,255,210,60],[209,255,160,50],[210,255,105,90],[211,255,60,150],
   [G_CYAN,0,70,100],[G_PINK,100,15,75],[G_BLUE,10,16,110],[G_PURPLE,55,20,105],[G_LIME,30,90,30],
   [C_PANEL,4,6,26],
   [C_KEY,248,0,248]].each { |a| M.fb_palette(a[0], a[1], a[2], a[3]) }
end

ATLAS_A = 2     # page: title card, finish card, sun, HUD panels, gauge face
ATLAS_B = 3     # page: grid card, subtitle

PACK_8 = "NEON_CIRCUIT_POLY_8.DAT"
PACK_4 = "NEON_CIRCUIT_POLY.DAT"
PACK_FILE = File.exist?(PACK_8) ? PACK_8 : PACK_4
STOP_MS = $NC_STOP || 50000      # the host check sets $NC_STOP to end early (the shown page is saved as a picture)

# ---- drawing used only while building the atlas ----
# Text centred on cx, top at y: a glow ring (offsets of 2), a black outline (offsets of 1), then the colour.
def neon_text(fb, s, cx, y, height, color, glow = nil, outline = true)
  fb.font(M::FONT_ROM, height, M::FW_BOLD).bk(M::BK_TRANSPARENT)
  if glow
    fb.text_color(glow, M::TA_CENTER | M::TA_TOP)
    [[-3, 0], [3, 0], [0, -3], [0, 3], [-2, -2], [2, -2], [-2, 2], [2, 2]].each { |d| fb.text_out(cx + d[0], y + d[1], s) }
  end
  if outline
    fb.text_color(C_BLACK, M::TA_CENTER | M::TA_TOP)
    [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]].each { |d| fb.text_out(cx + d[0], y + d[1], s) }
  end
  fb.text_color(color, M::TA_CENTER | M::TA_TOP).text_out(cx, y, s)
end

# A rounded neon frame: a wide dim pen, a middle one, then a thin bright line (no fill).
def neon_frame(fb, l, t, r, b, round, color, glow)
  fb.brush(0, M::BS_NULL)
  fb.pen(glow, 7).round_rect(l, t, r, b, round, round)
  fb.pen(color, 3).round_rect(l, t, r, b, round, round)
  fb.pen(C_WHITE, 1).round_rect(l + 1, t + 1, r - 1, b - 1, round, round)
end

def neon_ellipse(fb, cx, cy, rx, ry, color, glow)
  fb.brush(0, M::BS_NULL)
  fb.pen(glow, 5).ellipse(cx - rx, cy - ry, cx + rx, cy + ry)
  fb.pen(color, 1).ellipse(cx - rx, cy - ry, cx + rx, cy + ry)
end

# A neon "card" at (ox, oy), w x h: a black panel, two rings, two rounded frames.
# The panel is a plain rectangle so that the card is copied without the transparent key
# (a keyed blit of 516 x 190 takes 42 ms on the device, a plain one a fraction of that).
def draw_card(fb, ox, oy, w, h, outer, outer_glow, inner, inner_glow, rings)
  fb.fill_rect(ox, oy, w, h, C_BLACK)
  if rings
    neon_ellipse(fb, ox + w / 2, oy + h / 2 - 2, 224, 70, C_BLUE, G_BLUE)
    neon_ellipse(fb, ox + w / 2, oy + h / 2 - 2, 184, 52, C_PURPLE, G_PURPLE)
  end
  neon_frame(fb, ox + 4, oy + 4, ox + w - 4, oy + h - 4, 26, outer, outer_glow)
  neon_frame(fb, ox + 16, oy + 16, ox + w - 16, oy + h - 16, 16, inner, inner_glow)
end

# Synthwave sun (128 x 64 at ox, oy): a disk cut at the horizon, one colour band at a time through
# the clip rectangle, with gaps that widen toward the horizon (cut back to the transparent key).
def draw_sun(fb, ox, oy)
  fb.pen(0, 1, M::PS_NULL)
  4.times do |b|
    fb.clip(ox, oy + b * 16, ox + 128, oy + b * 16 + 16)
    fb.brush(SUN[b]).ellipse(ox + 4, oy + 3, ox + 124, oy + 123)
  end
  fb.clip
  dy = 0
  while dy < 28
    fb.fill_rect(ox, oy + 63 - dy, 128, 1, C_KEY) if (dy % 7) < (4 - dy / 7)
    dy += 1
  end
end

# A HUD panel (150 x 25 at ox, oy) with empty bar tracks.
def draw_panel(fb, ox, oy, color, glow)
  fb.pen(0, 1, M::PS_NULL).brush(C_PANEL).round_rect(ox + 1, oy + 1, ox + 149, oy + 24, 10, 10)
  fb.brush(0, M::BS_NULL).pen(glow, 3).round_rect(ox + 2, oy + 2, ox + 148, oy + 23, 10, 10)   # the wide pen stays inside 150 x 25
  fb.pen(color, 1).round_rect(ox + 2, oy + 2, ox + 148, oy + 23, 10, 10)
  fb.fill_rect(ox + 6, oy + 5, 138, 5, C_DARK)
  fb.fill_rect(ox + 6, oy + 15, 138, 4, C_DARK)
end

GAUGE_X = 70      # centre of the speed gauge on the screen
GAUGE_Y = 446
GAUGE_R = 44

# The gauge face (104 x 60 at ox, oy): a dark half ring with tick marks.
def draw_gauge_face(fb, ox, oy)
  cx = ox + 52
  cy = oy + 52
  fb.brush(0, M::BS_NULL).pen(G_BLUE, 9).pen_ext(M::CAP_FLAT, M::JOIN_ROUND)
  fb.move_to(cx - GAUGE_R, cy).angle_arc(cx, cy, GAUGE_R, 180, -180)
  fb.pen(C_BLUE, 1)
  i = 0
  while i <= 10
    a = Math::PI * (1.0 - i / 10.0)
    r0 = i % 5 == 0 ? GAUGE_R - 10 : GAUGE_R - 6
    fb.move_to(cx + (r0 * Math.cos(a)).round, cy - (r0 * Math.sin(a)).round)
    fb.line_to(cx + ((GAUGE_R - 2) * Math.cos(a)).round, cy - ((GAUGE_R - 2) * Math.sin(a)).round)
    i += 1
  end
  fb.pen_ext(M::CAP_ROUND, M::JOIN_ROUND)
end

# where the small sprites sit in atlas page A (under the two cards)
SUN_X = 0
SUN_Y = 384
PANEL_X = 132
PANEL_Y0 = 384
PANEL_Y1 = 412
FACE_X = 290
FACE_Y = 384

LABELS = ["CITY CANYON", "OVERTAKE", "HIGH SPEED", "FINAL RUN"]

def build_atlas(fb)
  M.write_page = ATLAS_A
  fb.clear(C_KEY)
  fb.reset_drawing
  # title card (516x190) at (0, 0)
  draw_card(fb, 0, 0, 516, 190, C_CYAN, G_CYAN, C_BLUE, G_BLUE, true)
  neon_text(fb, "NEON CIRCUIT", 258, 40, 48, C_WHITE, G_PINK)
  neon_text(fb, "POLYGON RACE", 258, 104, 32, C_CYAN, G_CYAN)
  # finish card (520x188) at (0, 192)
  draw_card(fb, 0, 192, 520, 188, C_CYAN, G_CYAN, C_HOTPINK, G_PINK, true)
  neon_text(fb, "RACE COMPLETE", 260, 222, 48, C_WHITE, G_PINK)
  neon_text(fb, "CHECKERED FLAG", 260, 282, 32, C_CYAN, G_CYAN)
  neon_text(fb, "NEON CIRCUIT", 260, 328, 16, C_LIME, nil, false)
  # the strip under the cards (y 384..479; the column right of the cards is only 120 wide):
  # sun (128x64) at (0, 384), HUD panels (150x25) at (132, 384) and (132, 412), speed gauge face (104x60) at (290, 384)
  draw_sun(fb, SUN_X, SUN_Y)
  draw_panel(fb, PANEL_X, PANEL_Y0, C_CYAN, G_CYAN)
  draw_panel(fb, PANEL_X, PANEL_Y1, C_BLUE, G_BLUE)
  draw_gauge_face(fb, FACE_X, FACE_Y)

  M.write_page = ATLAS_B
  fb.clear(C_KEY)
  # grid card (396x160) at (0, 0)
  draw_card(fb, 0, 0, 396, 160, C_HOTPINK, G_PINK, C_CYAN, G_CYAN, false)
  neon_text(fb, "GRID READY", 198, 22, 48, C_WHITE, G_PURPLE)
  # subtitle at (0, 168), 400x20, transparent background
  neon_text(fb, "MEGACITY HIGHWAY GRAND PRIX", 200, 170, 16, C_LIME, nil, true)
  fb.reset_drawing
end

# ---- per frame ----
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
  fb.blit(SUN_X, SUN_Y, 128, 64, sun_x - 64, hy - 64, ATLAS_A, C_KEY) if hy < 544
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
  # neon edges, 2 pixels thick: two 1-pixel lines side by side (across the line's main direction).
  # A 2-pixel pen (pen(c, 2) + move_to / line_to) looks the same but costs 13 times as much on the
  # device (1.29 ms against 0.18 ms a line, 72 lines a frame).
  tl = M.ms
  k = 0
  while k < nl
    x0 = a[j]
    y0 = a[j + 1]
    x1 = a[j + 2]
    y1 = a[j + 3]
    c = PAL[a[j + 4]]
    fb.line(x0, y0, x1, y1, c)
    if (x1 - x0).abs > (y1 - y0).abs
      fb.line(x0, y0 + 1, x1, y1 + 1, c)
    else
      fb.line(x0 + 1, y0, x1 + 1, y1, c)
    end
    j += 5
    k += 1
  end
  $ms_lines += M.ms - tl
end

def race_time(elapsed)
  r = elapsed - 4.2
  r < 0 ? 0.0 : r
end

def draw_hud(fb, elapsed, frame)
  pulse = (frame * 7) % 104
  fb.blit(PANEL_X, PANEL_Y0, 150, 25, 12, 10, ATLAS_A, C_KEY)
  fb.fill_rect(18, 15, pulse, 5, C_LIME)
  fb.fill_rect(18, 25, (frame * 3) % 138, 4, C_HOTPINK)
  fb.blit(PANEL_X, PANEL_Y1, 150, 25, 478, 10, ATLAS_A, C_KEY)
  fb.fill_rect(484, 15, 138 - pulse, 5, C_CYAN)
  fb.fill_rect(484, 25, (frame * 11) % 138, 4, C_PURPLE)
  # race clock and section name (ROM font, drawn as text every frame)
  race = race_time(elapsed)
  tenths = (race * 10).to_i
  clock = format("LAP %02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
  li = 0
  li = 1 if race >= 7.0
  li = 2 if race >= 20.0
  li = 3 if race >= 36.0
  fb.font(M::FONT_ROM, 16, M::FW_BOLD).bk(M::BK_TRANSPARENT)
  fb.text_color(C_WHITE, M::TA_LEFT | M::TA_TOP).text_out(16, 40, clock)
  fb.text_color(C_CYAN, M::TA_RIGHT | M::TA_TOP).text_out(624, 40, LABELS[li])
  # speed gauge: the face from the atlas, a needle arc and the number
  fb.blit(FACE_X, FACE_Y, 104, 60, GAUGE_X - 52, GAUGE_Y - 52, ATLAS_A, C_KEY)
  speed = race <= 0 ? 0 : (race < 6 ? race * 45 : 270 + 25 * Math.sin(race * 0.9)).to_i
  sweep = speed * 180 / 320
  if sweep > 0             # three 1-pixel arcs (a 5-pixel pen costs 3.8 ms, three thin arcs 0.8 ms)
    fb.pen(speed > 280 ? C_HOTPINK : C_LIME, 1)
    r = GAUGE_R - 2
    while r <= GAUGE_R + 2
      fb.move_to(GAUGE_X - r, GAUGE_Y).angle_arc(GAUGE_X, GAUGE_Y, r, 180, -sweep)
      r += 2
    end
  end
  fb.text_color(C_WHITE, M::TA_CENTER | M::TA_BOTTOM).text_out(GAUGE_X, GAUGE_Y + 2, speed.to_s)
  fb.font(M::FONT_8X8, 8).text_color(C_CYAN, M::TA_CENTER | M::TA_TOP).text_out(GAUGE_X, GAUGE_Y + 6, "KM/H")
  # corner brackets
  fb.line(616, 405, 628, 405, C_BLUE)
  fb.line(628, 405, 628, 420, C_BLUE)
  fb.line(612, 470, 628, 470, C_BLUE)
  fb.line(628, 455, 628, 470, C_BLUE)
end

def draw_cards(fb, elapsed)
  if elapsed < 2.8
    fb.blit(0, 0, 516, 190, 62, 126, ATLAS_A)
    fb.blit(0, 168, 400, 22, 120, 350, ATLAS_B, C_KEY)
  elsif elapsed < 4.2
    fb.blit(0, 0, 396, 160, 122, 150, ATLAS_B)
    n = (4.2 - elapsed).to_i + 1
    n = 1 if n < 1
    n = 3 if n > 3
    fb.font(M::FONT_ROM, 64, M::FW_BOLD).bk(M::BK_TRANSPARENT)
    fb.text_color(G_LIME, M::TA_CENTER | M::TA_TOP)
    [[-3, 0], [3, 0], [0, -3], [0, 3]].each { |d| fb.text_out(320 + d[0], 234 + d[1], n.to_s) }
    fb.text_color(C_LIME, M::TA_CENTER | M::TA_TOP).text_out(320, 234, n.to_s)
  elsif elapsed >= 45.5
    fb.blit(0, 192, 520, 188, 60, 132, ATLAS_A)
  end
end

def present
  M.display_page = $back
  $front, $back = $back, $front
  M.write_page = $back
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
  raise "the pack has " + npal.to_s + " colours (at most " + UI_BASE.to_s + ")" if npal > UI_BASE
  pb = f.read(npal * 3).bytes
  npal.times { |i| M.fb_palette(i, pb[i * 3], pb[i * 3 + 1], pb[i * 3 + 2]) }
  pal = Array.new(npal) { |i| i }
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
$ms_read = 0       # time split of the playback (logged at the end)
$ms_scene = 0
$ms_hud = 0
$ms_lines = 0
begin
  $nc_stage = "MODE"
  M.mode = 3
  M.text_visible = false
  fb = M.fb
  set_fixed_palette
  raise "needs 4 framebuffer pages" if M.pages < 4
  [0, 1].each { |p| M.write_page = p; fb.clear(C_BLACK) }
  $front = 0
  $back = 1
  M.display_page = 0
  M.write_page = 1
  # loading card, drawn directly
  draw_card(fb, 74, 150, 492, 180, C_CYAN, G_CYAN, C_BLUE, G_BLUE, false)
  neon_text(fb, "NEON CIRCUIT", 320, 190, 48, C_WHITE, G_PINK)
  neon_text(fb, "BUILDING SPRITES", 320, 254, 16, C_CYAN, nil, true)
  present
  t = M.ms
  $nc_stage = "ATLAS"
  build_atlas(fb)
  M.write_page = $back
  nc_log("ATLAS", "built in " + (M.ms - t).to_s + "ms")

  $nc_stage = "OPEN PACK"
  pk = open_pack(PACK_FILE)
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
  start = M.ms
  $ms_lines = 0
  nc_log("PLAYBACK_START", "duration=50s")

  $nc_stage = "PLAYBACK"
  last = 0
  shown = 1
  skipped = 0
  checkpoint = 0
  render_ms = 0
  worst_ms = 0
  sum_ms = 0
  while true
    k = M.key
    break if k == 113 || k == 27          # q / ESC
    el = M.ms - start
    break if el >= STOP_MS
    target = el * fps / 1000
    target = frame_count - 1 if target >= frame_count
    if target > last
      skipped += target - last - 1
      elapsed = target.to_f / fps
      t = M.ms
      fr = read_frame($pack, offs, target)
      t1 = M.ms
      draw_frame(fb, fr)
      t2 = M.ms
      draw_hud(fb, elapsed, target)
      draw_cards(fb, elapsed)
      present
      render_ms = M.ms - t
      $ms_read += t1 - t
      $ms_scene += t2 - t1
      $ms_hud += M.ms - t2
      sum_ms += render_ms
      worst_ms = render_ms if render_ms > worst_ms
      last = target
      shown += 1
    else
      M.vsync          # wait one display frame (about 17 ms)
    end
    c = (M.ms - start) / 5000
    if c > checkpoint
      checkpoint = c
      nc_log("PROGRESS", "elapsed=" + (M.ms - start).to_s + "ms shown=" + shown.to_s + " skipped=" + skipped.to_s +
             " frame=" + last.to_s + " render_ms=" + render_ms.to_s + " worst_ms=" + worst_ms.to_s)
    end
  end
  nc_log("DONE", "shown=" + shown.to_s + " skipped=" + skipped.to_s + " worst_ms=" + worst_ms.to_s +
         " avg_ms=" + (shown > 1 ? sum_ms / (shown - 1) : 0).to_s)
  n = shown > 1 ? shown - 1 : 1
  nc_log("SPLIT", "read=" + ($ms_read / n).to_s + " scene=" + ($ms_scene / n).to_s + " (lines " + ($ms_lines / n).to_s +
         ") hud+cards+flip=" + ($ms_hud / n).to_s + " ms a frame")
  vi = M.video_info
  puts "VIDEO underrun=#{vi[:underrun]} fifo_stall=#{vi[:fifo_stall]} recover=#{vi[:recover]} pair_max=#{vi[:pair_max].inspect}"
  $pack.close
  $pack = nil
rescue => e
  begin
    $pack.close if $pack
  rescue => e2
  end
  M.text_visible = true
  nc_log("ERROR", "stage=" + $nc_stage + " " + e.class.to_s + ": " + e.message.to_s)
  puts "NEON CIRCUIT ERROR"
  puts "STAGE: " + $nc_stage
  puts e.class.to_s + ": " + e.message.to_s
end
