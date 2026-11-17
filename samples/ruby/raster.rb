# Raster operation list demo (2026-10-28).
# Two uint8_t sine tables (512 and 384 entries, 128 = no move). Each frame the start position advances by 1
# (mod 512 / 384) and the values are copied to every display line: BG0 uses the 512 table, BG1 the 384 table,
# so the two meshes wave at independent frequencies. BG0 is a coarse mesh, BG1 a fine mesh.
# Objects and keys follow samples/ruby/testapp/mode3.rb (four disc sizes, pad/A, v, o/O, b, S).
# 3/4/5/6 mode, r raster list, b BG planes, o/O objects, v speed, S scroll, q/ESC ends.
M = Machine
lr = M.lowres
mode = 5
raster_on = true
scroll_on = true
bg_mask = 3
$obj_count = 24
$obj_demo = 1
$odiv = 4
$pox = 0.0; $poy = 0.0
$oph = 0.0
$ph0 = 0; $ph1 = 0
$sy0 = 0; $sy1 = 0; $sx1 = 0

TAB0 = Array.new(512) { |i| (128 + 96 * Math.sin(2 * Math::PI * i / 512)).to_i }.pack("C*")
TAB1 = Array.new(384) { |i| (128 + 96 * Math.sin(2 * Math::PI * i / 384 + 0.8)).to_i }.pack("C*")

# BG0: one mesh cell is 4x4 map tiles = 32x32 pixels (a 2-pixel border; the inside is transparent).
# BG1: one mesh cell is one 8x8 tile (a 1-pixel grid; the gaps are transparent).
COARSE = Array.new(32 * 32) { |i| x = i % 32; y = i / 32; (x < 2 || x >= 30 || y < 2 || y >= 30) ? 1 : 128 }
FINE   = Array.new(64) { |i| (i % 8) == 0 || (i / 8) == 0 ? 2 : 128 }
DISC_TILE = [340, 336, 320, 256]          # 8, 16, 32, 64 (tile = 64-byte unit)
DISC_SIZE = [8, 16, 32, 64]
SINT = Array.new(64) { |i| (127 * Math.sin(2 * Math::PI * i / 64)).to_i }
BARS = [[31, 31, 31], [31, 31, 0], [0, 31, 31], [0, 31, 0], [31, 0, 31], [31, 0, 0], [0, 0, 31], [0, 0, 0]]

def c8(v) = v * 255 / 31

# The framebuffer pattern of mode3.rb: 8 bars in the upper half, the CLUT8 ramps / CLUT4 colours below.
def draw_fb_pattern
  fb = M.fb
  bits = fb.bits_per_pixel
  BARS.each_with_index { |c, i| M.fb_palette(i, c8(c[0]), c8(c[1]), c8(c[2])) }
  if bits == 8
    32.times do |v|
      M.fb_palette(8 + v, c8(v), 0, 0); M.fb_palette(40 + v, 0, c8(v), 0)
      M.fb_palette(72 + v, 0, 0, c8(v)); M.fb_palette(104 + v, c8(v), c8(v), c8(v))
    end
    M.fb_palette(136, 255, 255, 255)
    grad = ->(band, v) { 8 + band * 32 + v }
    border = 136
  else
    8.times { |i| v = c8(i * 31 / 7); M.fb_palette(8 + i, v, v, v) }
    grad = ->(_band, v) { 8 + v }
    border = 0
  end
  8.times { |i| fb.fill_rect(i * 80, 0, 80, 240, i) }
  if bits == 4
    16.times { |i| fb.fill_rect(i * 40, 240, 40, 240, i) }
  else
    4.times { |band| 32.times { |v| fb.fill_rect(v * 20, 240 + band * 60, 20, 60, grad.(band, v)) } }
  end
  fb.rect(0, 0, 640, 480, border)
end

def ramp(pal, r, g, b)                    # 128 colours from dark to bright (mode3.rb)
  128.times { |c| Machine.lowres.palette(pal, c, r * 255 / 31 * c / 127, g * 255 / 31 * c / 127, b * 255 / 31 * c / 127) }
end

def disc(tile, size)                      # bright centre, darker edge, transparent outside (mode3.rb)
  c = size / 2; rr = c * c
  Machine.lowres.pattern(tile, Array.new(size * size) { |i|
    x = i % size - c; y = i / size - c; d = x * x + y * y
    d >= rr ? 128 : 127 - d * 127 / rr
  })
end

def setup_lowres
  lr = Machine.lowres
  lr.clear
  lr.pattern(0, [128] * 64)                # transparent tile for the inside of the coarse mesh
  lr.pattern(3, COARSE)                    # 32x32 = 16 tiles
  lr.pattern(2, FINE)
  lr.fill_map(0, 0, 0)
  64.times do |ty|                         # a 32x32 mesh block every 4x4 map tiles
    64.times { |tx| lr.map(0, tx, ty, 3, 0) if tx % 4 == 0 && ty % 4 == 0 }
  end
  lr.fill_map(1, 2, 0)
  # mesh palettes 8..15 (the raster CLUT base keeps objects on 1..5)
  8.times do |p|
    lr.palette(8 + p, 1, 255, 40 + p * 12, 0)
    lr.palette(8 + p, 2, 0, 120 + p * 8, 255 - p * 12)
    lr.palette(8 + p, 3, 240, 240, 240)
  end
  # objects: the five ramps of mode3.rb (white, green, orange, blue, red)
  ramp(1, 31, 31, 31); ramp(2, 8, 31, 12); ramp(3, 31, 22, 6); ramp(4, 10, 18, 31); ramp(5, 31, 10, 10)
  DISC_SIZE.each_with_index { |size, k| disc(DISC_TILE[k], size) }
end

def setup_raster_static
  lr = Machine.lowres
  lr.raster_clear
  y = 0
  while y < 480
    a = Math.sin(2 * Math::PI * y / 240)
    lr.backdrop(y, (64 + 48 * a).to_i, 24, (128 - 64 * a).to_i)
    lr.raster(0, y, 8 + (y / 12) % 8, 0, 0)
    lr.raster(1, y, 8 + (y / 6) % 8, 0, 0)
    y += 1
  end
end

def setup_objects(count, heavy = false)
  lr = Machine.lowres
  128.times { |i| lr.obj_hide(i) }
  count.times do |i|
    k = heavy ? 3 : i % 4
    w = DISC_SIZE[k]
    lr.obj(i, 160 - w / 2, 120 - w / 2, DISC_TILE[k], w, w, 1 + (i % 5), i % 3)
    lr.obj_move(i, 96 + (i % 8) * 4, 72 + (i / 8 % 8) * 4) if heavy
  end
  lr.obj_visible = true
end

def show_bg(bg_mask)
  lr = Machine.lowres
  lr.bg_visible(0, (bg_mask & 1) != 0)
  lr.bg_visible(1, (bg_mask & 2) != 0)
end

def pad_objects
  lx, ly = M.pad_stick(0, :left)
  dx, dy = M.pad_dir(0)
  vx = (lx != 0.0 ? lx * 4 : dx * 3) / $odiv.to_f
  vy = (ly != 0.0 ? ly * 4 : dy * 3) / $odiv.to_f
  $pox = ($pox + vx).clamp(-150.0, 150.0)
  $poy = ($poy + vy).clamp(-110.0, 110.0)
  ($pox = 0.0; $poy = 0.0) if M.pad_pressed?(0, M::PAD_A)
end

def move_objects(ph)
  return if $obj_count == 0
  ox = $pox.to_i; oy = $poy.to_i
  $obj_count.times do |i|
    w = DISC_SIZE[i % 4]
    # 位相は小数のまま使い、SINT の間を線形に補間する（mode4〜6 と同じ）。
    # 1/4 速さでも 4 フレームごとの飛びにならない。
    a = ph * (1 + (i & 3)) / 2.0 + i * 5
    b = ph * (1 + ((i >> 2) & 3)) / 3.0 + i * 11
    ai = a.to_i; af = a - ai
    bi = b.to_i; bf = b - bi
    sa = SINT[ai & 63] + (SINT[(ai + 1) & 63] - SINT[ai & 63]) * af
    sb = SINT[bi & 63] + (SINT[(bi + 1) & 63] - SINT[bi & 63]) * bf
    Machine.lowres.obj_move(i, (160 - w / 2 + ox + sa * 140 / 127).round,
                                (120 - w / 2 + oy + sb * 100 / 127).round)
  end
end

def help_text(mode)
  return if mode == 6
  M.text_clear(M::TEXT_CLEAR)
  M.text_put(1, 1, "RASTER 3-6: mode  r: list  b: BG  o/O: objects  v: speed  S: scroll  q: quit",
             M.tattr(15, 0, M::TEXT_BG_TRANSPARENT))
end

def start_mode(n, raster_on, bg_mask)
  M.mode = n
  M.text_visible = (n != 6)
  draw_fb_pattern if n == 3 || n == 4
  setup_lowres
  $obj_count = 24; $obj_demo = 1
  setup_objects(24)
  raster_on ? setup_raster_static : Machine.lowres.raster_clear
  show_bg(bg_mask)
  help_text(n)
  puts "raster: mode #{n} (raster #{raster_on ? "on" : "off"})"
end

start_mode(mode, raster_on, bg_mask)
$oph = 0.0
$olast = M.ms
loop do
  k = M.key || -1
  break if k == 113 || k == 27
  if k >= 51 && k <= 54
    mode = k - 48
    start_mode(mode, raster_on, bg_mask)
  elsif k == 114                             # r
    raster_on = !raster_on
    raster_on ? setup_raster_static : lr.raster_clear
    help_text(mode)
    puts "raster: list #{raster_on ? "on" : "off"}"
  elsif k == 98                              # b
    bg_mask = (bg_mask + 1) & 3
    show_bg(bg_mask)
    puts "raster: BG #{bg_mask}"
  elsif k == 111                             # o
    if $obj_count == 0 then $obj_count = 24; $obj_demo = 1
    elsif $obj_count >= 128 then $obj_count = 0; $obj_demo = 0; lr.obj_visible = false
    else $obj_count *= 2; $obj_count = 128 if $obj_count > 128; $obj_demo = 1
    end
    setup_objects($obj_count) if $obj_count > 0
    puts "raster: objects #{$obj_count}"
  elsif k == 79                              # O: load test
    if $obj_demo == 2 then $obj_count = 24; $obj_demo = 1; setup_objects(24)
    else $obj_count = 128; $obj_demo = 2; setup_objects(128, true)
    end
    puts "raster: load test #{$obj_demo == 2 ? "on" : "off"}"
  elsif k == 118                             # v
    $odiv = $odiv == 1 ? 4 : $odiv / 2
    puts "raster: speed 1/#{$odiv}"
  elsif k == 83                              # S
    scroll_on = !scroll_on
    puts "raster: scroll #{scroll_on ? "on" : "off"}"
  end
  if scroll_on
    if raster_on
      lr.raster_wave(0, TAB0, $ph0)
      lr.raster_wave(1, TAB1, $ph1)
      $ph0 = ($ph0 + 1) % 512
      $ph1 = ($ph1 + 1) % 384
    end
    # BG0 scrolls up (sy grows); BG1 scrolls down (sy shrinks) and right (sx shrinks) by one dot
    lr.scroll(0, 0, $sy0)
    lr.scroll(1, $sx1, $sy1)
    $sy0 = ($sy0 + 2) & 511
    $sy1 = ($sy1 - 2) & 511
    $sx1 = ($sx1 - 1) & 511
  end
  now = M.ms
  $oph += (now - $olast) * 60.0 / 1000.0 / $odiv
  $olast = now
  if $obj_count > 0 && $obj_demo == 1
    pad_objects
    move_objects($oph)
  end
  M.vsync
end
lr.clear                                # lowres raster list (backdrop / CLUT / scroll) back to defaults
M.mode = 2                              # the framebuffer is left untouched
puts "bye"
