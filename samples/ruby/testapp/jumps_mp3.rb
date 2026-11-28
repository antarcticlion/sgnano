# Title: side-scrolling jump action (screen mode 5, 3 stages x 16 screens)
# BGM: WTF4CH.mp3 via Machine::Music (VGM/MP3 player), 2026-11-11
# Platform: sgnano / mruby 4.0 / lowres 320x240 + text
# Keys: Left/Right move, Space/Up jump (or pad 0: dir + A)

SCREEN_W = 320
SCREEN_H = 240
TILE     = 8
MAP_W    = 64
MAP_H    = 64
CHARSZ   = 32
GRAVITY  = 0.55
MOVE_V   = 2.2
MAX_FALL = 7.0
# Jump arcs: a precomputed parabola.  The tables hold the vertical move for
# each 60 Hz physics step, so the rise and fall stay symmetric and no
# per-frame integration error accumulates.
JUMP_STEPS   = 34
JUMP_H       = 61.5
BOUNCE_STEPS = 21
BOUNCE_H     = 30.1

def arc_table(height, steps)
  dy = Array.new(steps)
  k = 0
  while k < steps
    a = -4.0 * height * k * (steps - k) / (steps * steps)
    k1 = k + 1
    b = -4.0 * height * k1 * (steps - k1) / (steps * steps)
    dy[k] = b - a
    k += 1
  end
  dy
end

JUMP_DY   = arc_table(JUMP_H, JUMP_STEPS)
BOUNCE_DY = arc_table(BOUNCE_H, BOUNCE_STEPS)
STAGES   = 3
SCREENS_PER_STAGE = 16
SCREEN_PX = SCREEN_W
STAGE_PX  = SCREENS_PER_STAGE * SCREEN_PX
COLS      = STAGE_PX / TILE
ROWS      = MAP_H
WINDOW_PX = MAP_W * TILE
MAP_MASK  = MAP_W - 1
GROUND_ROW = 56
SCROLL_Y   = (GROUND_ROW - 24) * TILE
MAP_ROW0   = SCROLL_Y / TILE
MAP_ROW1   = (SCROLL_Y + SCREEN_H - 1) / TILE

# BGM: the firmware's Music API (ABI 4.4) plays this file on port 0.
# The sound effects use port 1 (SE_CH) so they do not stop the BGM stream.
MUSIC_FILE = "WTF4CH.mp3"
MUSIC_PATHS = ["WTF4CH.mp3", "A:/testapp/WTF4CH.mp3", "S:/testapp/WTF4CH.mp3"]
DEBUG = false

# Scoring.  The base values are already doubled from the original game;
# every consecutive stomp bounce doubles the multiplier again.
COIN_PTS  = 200
STOMP_PTS = 400
GOAL_PTS  = 10000
COMBO_MAX = 8
POPUP_MS  = 1000
# Score popups and the goal stay opaque: ABI 1.8 removed the lowres object
# alpha, so the old fade / pulse that used it is gone.

# Background (BG1) parallax: the mountains and clouds move at a quarter
# of the terrain speed, which makes the hills feel far away.
BG_PARALLAX = 0.25
BG_ROWS     = 30              # visible background rows (0..29)
BG_GROUND_Y = 26 * TILE       # base of the mountain silhouettes (208)

# Per-stage background colours: sky, far range, near range, cloud, cloud
# shade, pit.  Stage 3 is a dusk palette so the red fortress feels hot.
STAGE_BG_COLORS = [
  [[ 96, 168, 236], [130, 160, 198], [ 84, 124, 112], [248, 250, 255], [198, 216, 240], [24, 22, 32]],
  [[ 72, 136, 220], [116, 152, 208], [ 76, 108, 160], [248, 250, 255], [206, 220, 244], [20, 20, 38]],
  [[204, 118,  86], [158,  92,  92], [104,  58,  68], [250, 220, 180], [218, 164, 130], [30, 16, 22]]
]

# The sky is a raster backdrop gradient (one colour per display line).
# Three stops: top, middle, horizon.  BG1's sky is transparent so this
# shows through; the mountains and clouds stay opaque.
STAGE_SKY_GRADIENT = [
  [[ 40,  96, 200], [ 96, 168, 236], [184, 222, 248]],
  [[ 28,  74, 170], [ 72, 136, 220], [156, 204, 244]],
  [[ 32,  14,  48], [150,  60,  78], [246, 168, 104]]
]
SKY_GRADIENT_MID = 0.55
SKY_GRADIENT_LINES = (GROUND_ROW * TILE - SCROLL_Y) * 2
DISPLAY_LINES = SCREEN_H * 2

# Stage 3 is enemy-heavy, so it keeps a safe landing pocket roughly every
# two screens.  Enemies within 16 columns of a pocket centre are removed,
# which leaves more than three character widths of clear space on both
# sides of the landing spot.
STAGE3_SAFE_COLS = [0, 88, 176, 250, 330, 414, 488, 568]
STAGE3_SAFE_HALF = 16

C_SKY      = 1
C_GROUND   = 2
C_BRICK    = 3
C_COIN     = 4
C_ENEMY    = 5
C_PLAYER   = 6
C_GOAL     = 7
C_MTN_FAR  = 8
C_MTN_NEAR = 9
C_CLOUD    = 10
C_CLOUD_SH = 11
C_PIT      = 12
C_GROUND_DK = 13
C_GROUND_LT = 14
C_TRANS = Machine::LowRes::TRANSPARENT

M = Machine
M.mode = 5
LR = M.lowres

LR.palette(0, C_SKY,    90, 160, 230)
LR.palette(0, C_GROUND,  90,  70,  40)
LR.palette(0, C_BRICK,  180, 110,  60)
LR.palette(0, C_COIN,   250, 220,  40)
LR.palette(0, C_ENEMY,  200,  40,  40)
LR.palette(0, C_PLAYER, 240, 240, 250)
LR.palette(0, C_GOAL,    40, 220, 120)
LR.palette(0, C_MTN_FAR, 130, 160, 198)
LR.palette(0, C_MTN_NEAR, 84, 124, 112)
LR.palette(0, C_CLOUD,   248, 250, 255)
LR.palette(0, C_CLOUD_SH, 198, 216, 240)
LR.palette(0, C_PIT,     24,  22,  32)
LR.palette(0, C_GROUND_DK, 64, 48, 28)
LR.palette(0, C_GROUND_LT, 120, 98, 60)
LR.palette(1, C_SKY,    90, 160, 230)
LR.palette(1, C_GROUND,  90,  70,  40)
LR.palette(1, C_BRICK,  180, 110,  60)
LR.palette(1, C_COIN,   250, 220,  40)
LR.palette(1, C_ENEMY,  200,  40,  40)
LR.palette(1, C_PLAYER, 240, 240, 250)
LR.palette(1, C_GOAL,    40, 220, 120)
LR.palette(1, C_MTN_FAR, 130, 160, 198)
LR.palette(1, C_MTN_NEAR, 84, 124, 112)
LR.palette(1, C_CLOUD,   248, 250, 255)
LR.palette(1, C_CLOUD_SH, 198, 216, 240)
LR.palette(1, C_PIT,     24,  22,  32)
LR.palette(1, C_GROUND_DK, 64, 48, 28)
LR.palette(1, C_GROUND_LT, 120, 98, 60)

def solid_tile(color)
  (0...64).map { color }.pack("C*")
end

# A soil tile with a light top edge, a dark bottom seam and a few pebbles.
# The repeating seams and pebbles make horizontal scrolling visible even
# on a long flat stretch.
def ground_tile
  buf = []
  8.times do |y|
    8.times do |x|
      c = if y == 0
            C_GROUND_LT
          elsif y == 7
            C_GROUND_DK
          elsif x == 0
            C_GROUND_DK
          elsif (x == 3 && y == 2) || (x == 6 && y == 4)
            C_GROUND_DK
          elsif (x == 2 && y == 5) || (x == 5 && y == 3)
            C_GROUND_LT
          else
            C_GROUND
          end
      buf << c
    end
  end
  buf.pack("C*")
end
LR.pattern(0, solid_tile(C_TRANS))
LR.pattern(1, ground_tile)
LR.pattern(2, solid_tile(C_BRICK))
LR.pattern(3, solid_tile(C_COIN))
LR.pattern(4, solid_tile(C_ENEMY))
LR.pattern(5, solid_tile(C_GOAL))
LR.pattern(6, solid_tile(C_SKY))
LR.pattern(7, solid_tile(C_PIT))

pl = []
CHARSZ.times do |y|
  CHARSZ.times do |x|
    inside = (x >= 4 && x < 28 && y >= 4 && y < 28)
    if inside
      if (y >= 10 && y < 14) && ((x >= 10 && x < 14) || (x >= 18 && x < 22))
        pl << 0
      else
        pl << C_PLAYER
      end
    else
      pl << C_TRANS
    end
  end
end
LR.pattern(16, pl.pack("C*"))

# Dot font for the score popups (one 8x8 pattern per digit).
# The zero is 3x5 and sits on the same baseline as the 3x7 digits.
DIGIT_GLYPHS = [
  ["###", "#.#", "#.#", "#.#", "###"],
  ["..#", ".##", "..#", "..#", "..#", "..#", "..#"],
  ["###", "..#", "..#", "###", "#..", "#..", "###"],
  ["###", "..#", "..#", "###", "..#", "..#", "###"],
  ["#.#", "#.#", "#.#", "###", "..#", "..#", "..#"],
  ["###", "#..", "#..", "###", "..#", "..#", "###"],
  ["###", "#..", "#..", "###", "#.#", "#.#", "###"],
  ["###", "..#", "..#", "..#", "..#", "..#", "..#"],
  ["###", "#.#", "#.#", "###", "#.#", "#.#", "###"],
  ["###", "#.#", "#.#", "###", "..#", "..#", "###"]
]
DIGIT_GLYPHS.each_with_index do |rows, d|
  h = rows.length
  top = 7 - h
  buf = []
  8.times do |y|
    8.times do |x|
      on = y >= top && y < top + h && x < 3 && rows[y - top][x] == "#"
      buf << (on ? C_COIN : C_TRANS)
    end
  end
  LR.pattern(32 + d, buf.pack("C*"))
end

# ---- Background layer (BG1) ----
# Tiles 0..63 are reserved for the game.  Background tiles start at 64 and
# are generated once at startup.  The BG1 map is a 512 px panorama that
# wraps; it is drawn behind the transparent sky cells of BG0.
BG_TILE_BASE = 64
$bg_next_tile = BG_TILE_BASE

def bg_sprite(rows)
  w = rows[0].length
  h = rows.length
  tw = (w + 7) / 8
  th = (h + 7) / 8
  out = []
  ty = 0
  while ty < th
    line = []
    tx = 0
    while tx < tw
      buf = []
      sky_only = true
      y = 0
      while y < 8
        x = 0
        while x < 8
          yy = ty * 8 + y
          xx = tx * 8 + x
          ch = (yy < h && xx < w) ? rows[yy][xx] : "."
          if ch == "#"
            buf << C_CLOUD
            sky_only = false
          elsif ch == "+"
            buf << C_CLOUD_SH
            sky_only = false
          else
            buf << C_TRANS
          end
          x += 1
        end
        y += 1
      end
      if sky_only
        line << nil
      else
        t = $bg_next_tile
        $bg_next_tile += 1
        LR.pattern(t, buf.pack("C*"))
        line << t
      end
      tx += 1
    end
    out << line
    ty += 1
  end
  [out, tw, th]
end

def bg_stamp(sprite, tx, row, flip = false)
  map, tw, th = sprite
  sy = 0
  while sy < th
    sx = 0
    while sx < tw
      tile = map[sy][sx]
      if tile
        if flip
          LR.map(1, tx + tw - 1 - sx, row + sy, tile, 0, true, false)
        else
          LR.map(1, tx + sx, row + sy, tile, 0)
        end
      end
      sx += 1
    end
    sy += 1
  end
end

def build_background
  sky_tile = 0
  far_tile = 49
  near_tile = 50
  LR.pattern(far_tile, solid_tile(C_MTN_FAR))
  LR.pattern(near_tile, solid_tile(C_MTN_NEAR))

  # Paint every visible cell with the transparent tile first.  BG1's sky
  # is transparent so the per-line raster backdrop gradient shows through.
  r = 0
  while r < BG_ROWS
    c = 0
    while c < 64
      LR.map(1, c, r, sky_tile, 0)
      c += 1
    end
    r += 1
  end

  # Two overlapping ridge lines.  Every sine has an integer number of
  # periods across the 512 px panorama, so the left and right edges match.
  far_h = Array.new(512, 0)
  near_h = Array.new(512, 0)
  x = 0
  while x < 512
    a = 2.0 * Math::PI * x / 512.0
    far_h[x] = (46.0 + 18.0 * Math.sin(a * 2.0 + 0.7) + 7.0 * Math.sin(a * 5.0 + 2.1)).to_i
    near_h[x] = (62.0 + 22.0 * Math.sin(a * 3.0 + 2.4) + 9.0 * Math.sin(a * 7.0 + 0.4)).to_i
    x += 1
  end

  tx = 0
  while tx < 64
    # Start at the highest point in this 8 px column.
    top_y = BG_GROUND_Y
    dx = 0
    while dx < 8
      x = tx * 8 + dx
      t = BG_GROUND_Y - far_h[x]
      top_y = t if t < top_y
      t = BG_GROUND_Y - near_h[x]
      top_y = t if t < top_y
      dx += 1
    end
    row = top_y / TILE
    row = 0 if row < 0
    while row <= BG_GROUND_Y / TILE
      y0 = row * TILE
      buf = []
      all_sky = true
      all_far = true
      all_near = true
      dy = 0
      while dy < 8
        dx = 0
        while dx < 8
          x = tx * 8 + dx
          y = y0 + dy
          if y >= BG_GROUND_Y - near_h[x]
            buf << C_MTN_NEAR
            all_sky = false
            all_far = false
          elsif y >= BG_GROUND_Y - far_h[x]
            buf << C_MTN_FAR
            all_sky = false
            all_near = false
          else
            buf << C_TRANS
            all_far = false
            all_near = false
          end
          dx += 1
        end
        dy += 1
      end
      if all_sky
        # already the transparent tile
      elsif all_near
        LR.map(1, tx, row, near_tile, 0)
      elsif all_far
        LR.map(1, tx, row, far_tile, 0)
      else
        t = $bg_next_tile
        $bg_next_tile += 1
        LR.pattern(t, buf.pack("C*"))
        LR.map(1, tx, row, t, 0)
      end
      row += 1
    end
    tx += 1
  end

  big = bg_sprite([
    "........................",
    "..........####..........",
    "........########........",
    "......############......",
    ".....##############.....",
    "....################....",
    "...##################...",
    "..####################..",
    "..####################..",
    "...##################...",
    "....################....",
    ".....##############.....",
    "......++++++++++++......",
    "........................",
    "........................",
    "........................"
  ])
  small = bg_sprite([
    "................",
    "....########....",
    "..############..",
    ".##############.",
    "################",
    ".++++++++++++++.",
    "................",
    "................"
  ])
  bg_stamp(big, 2, 2)
  bg_stamp(small, 10, 6, true)
  bg_stamp(big, 19, 3, true)
  bg_stamp(small, 29, 7)
  bg_stamp(big, 37, 1)
  bg_stamp(small, 47, 5, true)
  bg_stamp(big, 54, 4, true)
end

def apply_bg_palette(stage)
  c = STAGE_BG_COLORS[stage]
  LR.palette(0, C_SKY,      c[0][0], c[0][1], c[0][2])
  LR.palette(0, C_MTN_FAR,  c[1][0], c[1][1], c[1][2])
  LR.palette(0, C_MTN_NEAR, c[2][0], c[2][1], c[2][2])
  LR.palette(0, C_CLOUD,    c[3][0], c[3][1], c[3][2])
  LR.palette(0, C_CLOUD_SH, c[4][0], c[4][1], c[4][2])
  LR.palette(0, C_PIT,      c[5][0], c[5][1], c[5][2])
end

# A vertical sky gradient on the raster operation list.  The lowres plane
# is doubled to 640x480, so one logical row is two display lines.  The
# horizon is at the top of the ground; below it the colour is hidden by
# the terrain but keep the horizon colour for the full frame.
def apply_sky_gradient(stage)
  stops = STAGE_SKY_GRADIENT[stage]
  y = 0
  while y < SKY_GRADIENT_LINES
    t = y.to_f / (SKY_GRADIENT_LINES - 1)
    if t <= SKY_GRADIENT_MID
      c0 = stops[0]
      c1 = stops[1]
      u = t / SKY_GRADIENT_MID
    else
      c0 = stops[1]
      c1 = stops[2]
      u = (t - SKY_GRADIENT_MID) / (1.0 - SKY_GRADIENT_MID)
    end
    u = u * u * (3.0 - 2.0 * u)
    r  = (c0[0] + (c1[0] - c0[0]) * u).to_i
    g  = (c0[1] + (c1[1] - c0[1]) * u).to_i
    bl = (c0[2] + (c1[2] - c0[2]) * u).to_i
    LR.backdrop(y, r, g, bl)
    y += 1
  end
  c1 = stops[2]
  while y < DISPLAY_LINES
    LR.backdrop(y, c1[0], c1[1], c1[2])
    y += 1
  end
end

build_background

SE_CH = 1                       # port 1: sound effects (port 0 = the Music stream)
Sound.wave(SE_CH, Sound::SQUARE)
Sound.adsr(SE_CH, 0, 40, 60, 40)
Sound.volume(SE_CH, 100)
Sound.master(100)
$se_off_at = 0
def se_start(freq, ms, wave = Sound::SQUARE, noise = false)
  # The Music API uses port 0 for the VGM/MP3 stream; keep the effects on
  # port 1 so both can sound at the same time (2026-11-11).
  Sound.reserve(SE_CH, true)
  # ABI 1.4: NOISE_MODE gives the effect channel a percussion-like hit.
  # Switch back to WT before every tonal effect because the noise mode
  # ignores Sound.wave.
  if noise
    Sound.set_mode(SE_CH, Sound::NOISE_MODE)
  else
    Sound.set_mode(SE_CH, Sound::WT)
    Sound.wave(SE_CH, wave)
  end
  Sound.note_on(SE_CH, 69, 110)
  Sound.freq(SE_CH, freq)
  $se_off_at = M.ms + ms
end
def se_poll
  if $se_off_at > 0 && M.ms >= $se_off_at
    Sound.note_off(SE_CH)
    Sound.set_mode(SE_CH, Sound::WT)     # a noise effect must not leave the port in NOISE_MODE
    Sound.reserve(SE_CH, false)          # give port 0 back to the BGM
    $se_off_at = 0
  end
end
def se_jump;  se_start(520,  60, Sound::SQUARE);   end
def se_coin;  se_start(1040, 90, Sound::PULSE25);  end
def se_stomp; se_start(180,  70, Sound::TRIANGLE, true); end
def se_hurt;  se_start(140, 180, Sound::SAW);      end
def se_goal;  se_start(1320, 260, Sound::SQUARE);  end

def music_start
  path = MUSIC_PATHS.find { |p| File.exist?(p) } || MUSIC_FILE
  Machine::Music.play(path, true)
  puts "music: #{path} (MP3, looped)"
rescue => e
  puts "music: #{e.class}: #{e.message}"
end
def music_stop
  Machine::Music.stop if Machine::Music.playing?
end

def stage_ground(cols, c0, c1, top = GROUND_ROW)
  cx = c0
  while cx < c1
    if cx >= 0 && cx < COLS
      cy = top
      while cy < ROWS
        cols[cx][cy] = 1
        cy += 1
      end
    end
    cx += 1
  end
end

def stage_bricks(cols, c0, c1, top, thick = 1)
  cx = c0
  while cx < c1
    if cx >= 0 && cx < COLS
      cy = top
      last = top + thick
      while cy < last && cy < ROWS
        cols[cx][cy] = 2 if cy >= 0
        cy += 1
      end
    end
    cx += 1
  end
end

def stage_pit(cols, c0, c1)
  cx = c0
  while cx < c1
    if cx >= 0 && cx < COLS
      cy = 0
      while cy < ROWS
        cols[cx][cy] = 0
        cy += 1
      end
    end
    cx += 1
  end
end

def stage_coins(objects, c0, c1, row, step = 1)
  cx = c0
  while cx < c1
    objects << [3, cx * TILE, row * TILE, true] if cx >= 0 && cx < COLS && row >= 0 && row < ROWS
    cx += step
  end
end

def stage_enemies(objects, c0, c1, row, step = 1)
  cx = c0
  while cx < c1
    objects << [4, cx * TILE, row * TILE, true] if cx >= 0 && cx < COLS && row >= 0 && row < ROWS
    cx += step
  end
end

def stage_top_row(cols, cx)
  my = 0
  while my < ROWS
    return my if cols[cx][my] != 0
    my += 1
  end
  ROWS
end

def stage_enemies_auto(cols, objects, c0, c1, step)
  cx = c0
  while cx < c1
    top = stage_top_row(cols, cx)
    objects << [4, cx * TILE, (top - 1) * TILE, true] if top > 0 && top < ROWS
    cx += step
  end
end

def stage_coins_auto(cols, objects, c0, c1, step, above)
  cx = c0
  while cx < c1
    top = stage_top_row(cols, cx)
    row = top - above
    objects << [3, cx * TILE, row * TILE, true] if top < ROWS && row >= 0
    cx += step
  end
end

def stage_clear_enemy_pockets(objects)
  keep = []
  objects.each do |o|
    if o[0] == 4
      cx = (o[1] / TILE).to_i
      safe = false
      STAGE3_SAFE_COLS.each do |sc|
        if (cx - sc).abs <= STAGE3_SAFE_HALF
          safe = true
          break
        end
      end
      keep << o unless safe
    else
      keep << o
    end
  end
  keep
end

def build_stage(stage, cols = nil)
  if cols
    # Reuse the map of the stage we are leaving instead of allocating a
    # second 640x64 array (the mruby heap is only 1 MB on the device).
    # Stages only build terrain at row 50 or below; the base ground is
    # rewritten by stage_ground below.
    cx = 0
    while cx < COLS
      col = cols[cx]
      cy = 50
      while cy < GROUND_ROW
        col[cy] = 0
        cy += 1
      end
      cx += 1
    end
  else
    cols = Array.new(COLS) { Array.new(ROWS, 0) }
  end
  objects = []
  stage_ground(cols, 0, COLS)
  case stage
  when 0
    # --- 1: coins, first gap, first enemy, then one new idea per screen ---
    stage_coins(objects, 10, 18, 55, 2)
    stage_pit(cols, 52, 56)
    stage_coins(objects, 52, 56, 52)
    stage_coins(objects, 64, 68, 55, 2)
    stage_enemies(objects, 68, 69, 55)

    stage_ground(cols, 88, 104, 55)
    stage_coins(objects, 90, 102, 54, 3)

    stage_ground(cols, 112, 120, 54)
    stage_ground(cols, 120, 128, 52)
    stage_ground(cols, 128, 136, 50)
    stage_ground(cols, 136, 144, 52)
    stage_ground(cols, 144, 152, 54)
    stage_coins(objects, 122, 134, 49, 4)
    # Keep the crest clear: an enemy under a coin makes the coin look like it
    # bounces.  This one waits on the flat ground after the descent.
    stage_enemies(objects, 156, 157, 55)

    stage_pit(cols, 168, 172)
    stage_bricks(cols, 176, 182, 52)
    stage_coins(objects, 176, 182, 50, 2)
    stage_enemies(objects, 188, 189, 55)

    stage_bricks(cols, 208, 216, 52)
    stage_coins(objects, 208, 216, 50, 2)
    stage_enemies(objects, 228, 229, 55)

    stage_pit(cols, 252, 256)
    stage_pit(cols, 264, 268)
    stage_coins(objects, 252, 268, 52, 3)
    stage_enemies(objects, 272, 273, 55)

    stage_ground(cols, 292, 300, 54)
    stage_ground(cols, 300, 308, 52)
    stage_ground(cols, 308, 316, 50)
    stage_coins(objects, 296, 312, 48, 4)
    stage_enemies(objects, 304, 305, 51)

    stage_pit(cols, 328, 336)
    stage_bricks(cols, 330, 334, 53)
    stage_coins(objects, 328, 336, 51, 2)
    stage_enemies(objects, 348, 349, 55)

    stage_enemies(objects, 360, 361, 55)
    stage_enemies(objects, 368, 369, 55)
    stage_coins(objects, 360, 370, 54, 2)

    # a raised plateau and a drop: more ups and downs in the second half
    stage_ground(cols, 380, 396, 52)
    stage_coins(objects, 382, 394, 50, 4)
    stage_enemies_auto(cols, objects, 386, 387, 1)

    stage_pit(cols, 412, 418)
    stage_coins(objects, 412, 418, 52)
    stage_enemies(objects, 428, 429, 55)

    stage_pit(cols, 448, 472)
    stage_bricks(cols, 446, 454, 52)
    stage_bricks(cols, 458, 466, 52)
    stage_bricks(cols, 470, 478, 52)
    stage_coins(objects, 448, 472, 50, 2)
    stage_enemies(objects, 458, 459, 51)
    stage_enemies(objects, 470, 471, 51)

    stage_pit(cols, 488, 492)
    stage_pit(cols, 500, 504)
    stage_pit(cols, 512, 516)
    stage_coins(objects, 488, 516, 52, 4)
    stage_enemies(objects, 508, 509, 55)

    stage_ground(cols, 520, 528, 54)
    stage_ground(cols, 528, 536, 52)
    stage_ground(cols, 536, 544, 50)
    stage_ground(cols, 544, 552, 52)
    stage_coins(objects, 528, 544, 48, 4)
    stage_enemies(objects, 538, 539, 49)

    stage_pit(cols, 572, 578)
    stage_bricks(cols, 574, 577, 53)
    stage_coins(objects, 572, 578, 51, 2)
    stage_enemies(objects, 590, 591, 55)

    stage_coins(objects, 600, 620, 55, 4)
    objects << [5, (COLS-4)*TILE, 54*TILE, true]

  when 1
    # --- 2: athletic.  Narrow islands, gaps, and floating bricks. ---
    # A: stepping stones (0..99)
    stage_pit(cols, 16, 21)
    stage_pit(cols, 26, 31)
    stage_pit(cols, 36, 41)
    stage_pit(cols, 46, 51)
    stage_pit(cols, 56, 61)
    stage_pit(cols, 66, 71)
    stage_pit(cols, 76, 81)
    stage_pit(cols, 86, 91)
    stage_ground(cols, 21, 26, 54)
    stage_ground(cols, 31, 36, 56)
    stage_ground(cols, 41, 46, 54)
    stage_ground(cols, 51, 56, 52)
    stage_ground(cols, 61, 66, 54)
    stage_ground(cols, 71, 76, 56)
    stage_ground(cols, 81, 86, 54)
    stage_ground(cols, 91, 100, 56)
    stage_coins_auto(cols, objects, 21, 100, 3, 2)
    stage_enemies(objects, 97, 98, 55)

    # B: a staircase of islands up to row 50 and back down (100..199)
    stage_pit(cols, 112, 117)
    stage_pit(cols, 129, 135)
    stage_pit(cols, 147, 153)
    stage_pit(cols, 165, 171)
    stage_pit(cols, 183, 189)
    stage_ground(cols, 117, 129, 54)
    stage_ground(cols, 135, 147, 52)
    stage_ground(cols, 153, 165, 50)
    stage_ground(cols, 171, 183, 52)
    stage_ground(cols, 189, 200, 54)
    stage_coins_auto(cols, objects, 117, 200, 4, 2)

    # C: wide chasm crossed by three floating platforms (200..299)
    stage_pit(cols, 220, 260)
    stage_bricks(cols, 224, 232, 52, 2)
    stage_bricks(cols, 236, 244, 50, 2)
    stage_bricks(cols, 248, 256, 53, 2)
    stage_coins(objects, 224, 256, 48, 4)
    stage_coins_auto(cols, objects, 260, 300, 5, 2)
    stage_enemies(objects, 280, 281, 55)

    # D: narrow pillars over a deep pit (300..399)
    stage_pit(cols, 310, 400)
    stage_ground(cols, 314, 319, 54)
    stage_ground(cols, 324, 329, 56)
    stage_ground(cols, 334, 339, 52)
    stage_ground(cols, 344, 349, 54)
    stage_ground(cols, 354, 359, 56)
    stage_ground(cols, 364, 369, 52)
    stage_ground(cols, 374, 379, 54)
    stage_ground(cols, 384, 389, 56)
    stage_ground(cols, 394, 399, 53)
    [314, 324, 334, 344, 354, 364, 374, 384, 394].each do |cx|
      top = stage_top_row(cols, cx)
      stage_coins(objects, cx, cx + 1, top - 2)
    end

    # E: a wave of raised islands (400..499)
    stage_pit(cols, 416, 422)
    stage_pit(cols, 430, 436)
    stage_pit(cols, 444, 450)
    stage_pit(cols, 458, 464)
    stage_pit(cols, 472, 478)
    stage_pit(cols, 486, 492)
    stage_ground(cols, 422, 430, 54)
    stage_ground(cols, 436, 444, 52)
    stage_ground(cols, 450, 458, 50)
    stage_ground(cols, 464, 472, 52)
    stage_ground(cols, 478, 486, 54)
    stage_coins_auto(cols, objects, 422, 492, 3, 2)
    stage_enemies(objects, 502, 503, 55)

    # F: rapid platform hopping (500..599)
    stage_pit(cols, 510, 600)
    stage_bricks(cols, 512, 518, 53, 2)
    stage_bricks(cols, 522, 528, 55, 2)
    stage_bricks(cols, 532, 538, 52, 2)
    stage_bricks(cols, 542, 548, 54, 2)
    stage_bricks(cols, 552, 558, 51, 2)
    stage_bricks(cols, 562, 568, 53, 2)
    stage_bricks(cols, 572, 578, 55, 2)
    stage_bricks(cols, 582, 588, 52, 2)
    stage_bricks(cols, 592, 598, 54, 2)
    stage_coins(objects, 512, 598, 49, 6)

    stage_coins(objects, 602, 624, 55, 4)
    stage_enemies(objects, 612, 613, 55)
    objects << [5, (COLS-4)*TILE, 54*TILE, true]

  else
    # --- 3: enemy-heavy.  Moderate terrain, many enemies everywhere. ---
    stage_pit(cols, 100, 104)
    stage_pit(cols, 160, 166)
    stage_pit(cols, 220, 224)
    stage_pit(cols, 280, 286)
    stage_pit(cols, 340, 344)
    stage_pit(cols, 400, 406)
    stage_pit(cols, 460, 464)
    stage_pit(cols, 520, 526)
    stage_pit(cols, 580, 584)

    stage_ground(cols, 40, 56, 54)
    stage_ground(cols, 120, 136, 54)
    stage_ground(cols, 180, 196, 52)
    stage_ground(cols, 240, 256, 54)
    stage_ground(cols, 300, 316, 52)
    stage_ground(cols, 360, 376, 54)
    stage_ground(cols, 420, 436, 52)
    stage_ground(cols, 480, 496, 54)
    stage_ground(cols, 540, 556, 52)
    stage_ground(cols, 600, 616, 54)

    stage_bricks(cols, 70, 78, 52)
    stage_bricks(cols, 90, 98, 50)
    stage_bricks(cols, 145, 153, 52)
    stage_bricks(cols, 205, 213, 50)
    stage_bricks(cols, 265, 273, 52)
    stage_bricks(cols, 325, 333, 50)
    stage_bricks(cols, 385, 393, 52)
    stage_bricks(cols, 445, 453, 50)
    stage_bricks(cols, 505, 513, 52)
    stage_bricks(cols, 565, 573, 50)

    stage_coins_auto(cols, objects, 0, 640, 8, 2)
    stage_enemies_auto(cols, objects, 20, 620, 11)
    # extra clusters, offset from the main line
    stage_enemies_auto(cols, objects, 243, 279, 6)
    stage_enemies_auto(cols, objects, 423, 459, 6)
    stage_enemies_auto(cols, objects, 563, 599, 7)
    objects = stage_clear_enemy_pockets(objects)

    stage_coins(objects, 620, 632, 55, 3)
    objects << [5, (COLS-4)*TILE, 54*TILE, true]
  end
  objects.uniq!
  [cols, objects]
end

def fill_map_column(cols, wc)
  mx = wc & MAP_MASK
  my = MAP_ROW0
  while my <= MAP_ROW1
    t = (wc >= 0 && wc < COLS) ? cols[wc][my] : 0
    tile = case t
           when 0 then (my >= GROUND_ROW ? 7 : 0)
           when 1 then 1
           when 2 then 2
           else 0
           end
    LR.map(0, mx, my, tile, 0)
    my += 1
  end
end

# The lowres map is a 64-column ring: world column wc lives in cell
# wc & 63.  Keep the loaded window [lo, hi] over the screen plus a lead,
# and write only one new column (30 visible rows) per frame.
def update_map_window(cols, cam_x)
  left = (cam_x / TILE).to_i
  right = ((cam_x + SCREEN_W - 1) / TILE).to_i

  if left < $ring_lo - 1 || right > $ring_hi + 1
    # a jump (respawn or stage change): rebuild just what is on screen
    (left..right).each { |wc| fill_map_column(cols, wc) }
    $ring_lo = left
    $ring_hi = right
  else
    if left < $ring_lo
      fill_map_column(cols, left)
      $ring_lo = left
    end
    if right > $ring_hi
      fill_map_column(cols, right)
      $ring_hi = right
    end
  end

  while $ring_hi - $ring_lo + 1 > MAP_W
    if $ring_lo < left
      $ring_lo += 1
    elsif $ring_hi > right
      $ring_hi -= 1
    else
      break
    end
  end

  if $ring_hi < left + MAP_W - 1
    wc = $ring_hi + 1
    fill_map_column(cols, wc)
    $ring_hi = wc
    $ring_lo += 1 if $ring_hi - $ring_lo + 1 > MAP_W
  end

  $base = $ring_lo
end

$score = 0
$stage = 0
$lives = 3
$combo = 0
$popups = []
$state = :play
$base = 0
$ring_lo = 0
$ring_hi = -1
$surface_row = []

# Lowest solid row of every column, or ROWS for a bottomless column.  The
# terrain only changes when a stage is loaded, so this is computed once and
# keeps the respawn search cheap on the device.
def compute_surface_rows(cols)
  rows = Array.new(COLS)
  cx = 0
  while cx < COLS
    # The surface is the top of the lowest solid run: the tile itself is
    # solid and the tile above it is empty.  Scanning from the bottom
    # prefers the ground over a floating brick higher up.
    r = ROWS - 1
    found = ROWS
    while r >= 0
      if cols[cx][r] != 0 && (r == 0 || cols[cx][r - 1] == 0)
        found = r
        break
      end
      r -= 1
    end
    rows[cx] = found
    cx += 1
  end
  rows
end

def load_stage(stage, old_cols = nil)
  # The mruby heap is only 1 MB.  A stage reload replaces the object list
  # and all of its small arrays; collect the previous stage's garbage
  # before building the next one (the map itself is reused through
  # old_cols).  Without this, the third stage can hit Out of memory.
  GC.start
  apply_bg_palette(stage)
  apply_sky_gradient(stage)
  cols, objects = build_stage(stage, old_cols)
  $surface_row = compute_surface_rows(cols)
  $base = 0
  $ring_lo = 0
  $ring_hi = -1
  update_map_window(cols, 0.0)
  LR.scroll(0, 0, SCROLL_Y)
  LR.scroll(1, 0, 0)
  LR.obj_visible = true
  LR.bg_visible(0, true)
  LR.bg_visible(1, true)
  [cols, objects]
end

music_start

cols, objects = load_stage($stage)
px = 32.0
py = GROUND_ROW * TILE - CHARSZ
vx = 0.0; vy = 0.0
on_ground = false
jump_dy = nil
jump_i = 0
jump_n = 0
cam_x = 0.0
$state = :play
M.clear_keys
M.text_clear(M::TEXT_CLEAR)
TA = M::TEXT_BG_TRANSPARENT

def solid_at(cols, wx, wy)
  cx = (wx / TILE).to_i
  cy = (wy / TILE).to_i
  return false if cx < 0 || cx >= COLS || cy < 0 || cy >= ROWS
  cols[cx][cy] == 1 || cols[cx][cy] == 2
end

# ---- Safe respawn search ----
# A landing spot must have a clear 32x32 body and a full-width solid row
# under both feet.  The lowest such surface is used, so the player lands
# on the ground rather than on a floating brick when both exist.
def respawn_body_clear?(cols, x, y)
  cx = (x / TILE).to_i
  cy = (y / TILE).to_i
  dy = 0
  while dy < 4
    dx = 0
    while dx < 4
      return false if cols[cx + dx][cy + dy] != 0
      dx += 1
    end
    dy += 1
  end
  true
end

# Surface y for a tile-aligned x.  All four body columns must end at the
# same row, and the 4x4 body above it must be empty.
def respawn_y_at(cols, x)
  cx = (x / TILE).to_i
  r = $surface_row[cx]
  return nil if r >= ROWS
  return nil unless $surface_row[cx + 1] == r &&
                    $surface_row[cx + 2] == r &&
                    $surface_row[cx + 3] == r
  y = r * TILE - CHARSZ
  return nil unless respawn_body_clear?(cols, x, y)
  y
end

# Horizontal clearance between the player's body and the nearest active
# enemy.  Three character widths (96 px) is the respawn rule.
def enemy_gap_x(enemies, x)
  gap = 9999
  enemies.each do |ex|
    g = if ex + 8 <= x
          x - (ex + 8)
        elsif ex >= x + CHARSZ
          ex - (x + CHARSZ)
        else
          0
        end
    gap = g if g < gap
  end
  gap
end

def find_respawn(cols, objects, death_x)
  max_x = STAGE_PX - CHARSZ
  target = death_x.to_i - SCREEN_W
  target = 0 if target < 0
  target = max_x if target > max_x
  target = (target / TILE).to_i * TILE

  enemies = []
  objects.each { |o| enemies << o[1] if o[0] == 4 && o[3] }

  # Walk outward from the target and take the first safe spot.  This is
  # normally only a few checks, and it avoids the old full-stage scan that
  # froze the device for 12 seconds after a side hit.
  [CHARSZ * 3, CHARSZ * 2, CHARSZ, 0].each do |need|
    off = 0
    while off <= STAGE_PX
      signs = (off == 0) ? [-1] : [-1, 1]
      signs.each do |sign|
        x = target + sign * off
        next if x < 0 || x > max_x
        y = respawn_y_at(cols, x)
        next unless y
        next if enemy_gap_x(enemies, x) < need
        return [x.to_f, y.to_f]
      end
      off += TILE
    end
  end

  [32.0, GROUND_ROW * TILE - CHARSZ]
end

def add_popup(wx, wy, value)
  digits = []
  v = value
  loop do
    digits.unshift(v % 10)
    v /= 10
    break if v == 0
  end
  $popups << [wx, wy, digits, M.ms + POPUP_MS]
  $popups.shift if $popups.length > 8
end

def draw_popups(cam_x, scroll_y, n)
  now = M.ms
  i = 0
  while i < $popups.length
    p = $popups[i]
    remain = p[3] - now
    if remain <= 0
      $popups.delete_at(i)
      next
    end
    age = POPUP_MS - remain
    digits = p[2]
    sx = p[0] - cam_x - (digits.length * 4) / 2
    sy = p[1] - scroll_y - age / 90
    if sx > -32 && sx < SCREEN_W + 16 && sy > -16 && sy < SCREEN_H + 16
      k = 0
      while k < digits.length && n < 64
        LR.obj(n, sx + k * 4, sy, 32 + digits[k], 8, 8, 1, 2)
        n += 1
        k += 1
      end
    end
    i += 1
  end
  n
end

def draw_objects(objects, cam_x, scroll_y)
  n = 1
  objects.each do |o|
    type, wx, wy, alive = o
    next unless alive
    sx = wx - cam_x
    next if sx < -CHARSZ || sx > SCREEN_W
    sy = wy - scroll_y
    next if sy < -CHARSZ || sy > SCREEN_H
    tile = case type
           when 3 then 3
           when 4 then 4
           when 5 then 5
           end
    LR.obj(n, sx, sy, tile, 8, 8, 1, 2)
    n += 1
    break if n >= 40
  end
  # Score popups go on top of the stage objects.
  n = draw_popups(cam_x, scroll_y, n)
  # Hide only the slots used in the previous frame (slot 0 is the player).
  i = n
  while i < $obj_shown
    LR.obj_hide(i)
    i += 1
  end
  $obj_shown = n
end

def read_dir
  dx = 0
  if M.pad(0) != nil
    pdir = M.pad_dir(0)
    if pdir != nil && pdir.is_a?(Array) && pdir[0].is_a?(Integer)
      d = pdir[0]
      dx = -1 if d < 0
      dx = 1  if d > 0
    end
  end
  dx = -1 if M.key_down?(M::KEY_LEFT)
  dx = 1  if M.key_down?(M::KEY_RIGHT)
  dx
end

def pad_jump?
  return true if M.pad_pressed?(0, M::PAD_A)
  if M.pad(0) != nil
    pdir = M.pad_dir(0)
    return true if pdir != nil && pdir.is_a?(Array) && pdir[1].is_a?(Integer) && pdir[1] < 0
  end
  false
end

def kb_jump?
  M.key_down?(M::KEY_SPACE) || M.key_down?(M::KEY_UP)
end

def move_x(px, py, vx, cols)
  nx = px + vx
  if vx > 0
    rx = nx + CHARSZ - 1
    if solid_at(cols, rx, py + 4) || solid_at(cols, rx, py + CHARSZ - 4)
      nx = (rx / TILE).to_i * TILE - CHARSZ
    end
  elsif vx < 0
    if solid_at(cols, nx, py + 4) || solid_at(cols, nx, py + CHARSZ - 4)
      nx = ((nx / TILE).to_i + 1) * TILE
    end
  end
  nx
end

def move_y(px, py, vy, cols)
  ny = py + vy
  if vy >= 0
    feet = ny + CHARSZ
    if solid_at(cols, px + 4, feet) || solid_at(cols, px + CHARSZ - 4, feet)
      cy = (feet / TILE).to_i
      ny = cy * TILE - CHARSZ
      return [ny, 0.0, true]
    end
    return [ny, vy, false]
  else
    head = ny
    if solid_at(cols, px + 4, head) || solid_at(cols, px + CHARSZ - 4, head)
      cy = (head / TILE).to_i
      ny = (cy + 1) * TILE
      return [ny, 0.0, false]
    end
    return [ny, vy, false]
  end
end

$last_ms = nil
$acc = 0.0
$obj_shown = 1
$hud_stage = -1
$hud_score = -1
$hud_lives = -1
$hud_pos = -1

loop do
  M.vsync
  se_poll

  if $state == :play
    # Fixed 60 Hz physics.  If a frame is late (GC, sound work, a
    # dropped vsync), run the missed step so the jump arc and the
    # walking speed keep the same real-time length.
    _now = M.ms
    if $last_ms
      $acc += _now - $last_ms
    else
      $acc = 16.6667
    end
    $last_ms = _now
    $acc = 33.3334 if $acc > 33.3334
    _steps = 0
    while $acc >= 16.0 && _steps < 2
      $acc -= 16.6667
      _steps += 1
      dx = read_dir

      if dx != 0
        vx = dx * MOVE_V
      else
        vx = 0.0
      end

      jump = pad_jump? || kb_jump?
      if jump && on_ground
        jump_dy = JUMP_DY
        jump_i = 0
        jump_n = JUMP_STEPS
        on_ground = false
        se_jump
      end

      if jump_dy
        if jump_i < jump_n
          vy = jump_dy[jump_i]
          jump_i += 1
        else
          # The parabolic arc is over (the landing is lower than take-off).
          jump_dy = nil
          vy = MAX_FALL
        end
      else
        vy += GRAVITY
        vy = MAX_FALL if vy > MAX_FALL
      end

      vy_before = vy

      px = move_x(px, py, vx, cols)
      px = 0.0 if px < 0
      px = STAGE_PX - CHARSZ if px > STAGE_PX - CHARSZ

      py, vy, on_ground = move_y(px, py, vy, cols)

      # A landing or a ceiling hit ends the parabolic arc.
      jump_dy = nil if jump_dy && (on_ground || vy == 0.0)

      # Touching the ground ends the stomp combo.
      $combo = 0 if on_ground && $combo > 0

      if py > ROWS * TILE + 64
        $combo = 0
        $popups.clear
        $lives -= 1
        se_hurt
        $state = ($lives <= 0) ? :gameover : :dead
      end

      # stomp one enemy per frame: on stomp, bounce and break so we do not
      # check any other enemy at the same position.
      objects.each do |o|
        next unless o[3]
        type, wx, wy = o[0], o[1], o[2]
        if px < wx + 8 && px + CHARSZ > wx && py < wy + 8 && py + CHARSZ > wy
          case type
          when 3
            o[3] = false
            pts = COIN_PTS << $combo
            $score += pts
            add_popup(wx + 4, wy - 10, pts)
            se_coin
          when 4
            if vy_before > 0 && (py + CHARSZ - vy_before) <= wy + 4
              o[3] = false
              $combo += 1 if $combo < COMBO_MAX
              pts = STOMP_PTS << ($combo - 1)
              $score += pts
              # move the player up a bit so the next frame does not re-hit
              # the same spot (other enemies at the same height are skipped).
              py = wy - CHARSZ
              add_popup(px + CHARSZ / 2, py - 12, pts)
              # A smaller parabolic hop for the stomp bounce.
              jump_dy = BOUNCE_DY
              jump_i = 0
              jump_n = BOUNCE_STEPS
              on_ground = false
              vy = jump_dy[0]
              se_stomp
              break
            else
              $combo = 0
              $lives -= 1; se_hurt
              $state = ($lives <= 0) ? :gameover : :dead
              break
            end
          when 5
            $combo = 0
            $score += GOAL_PTS; se_goal; $state = :clear
            break
          end
        end
      end

      break if $state != :play
    end

    if $state == :play
      target_cam = px - SCREEN_W / 2
      target_cam = 0.0 if target_cam < 0
      target_cam = STAGE_PX - SCREEN_W if target_cam > STAGE_PX - SCREEN_W
      cam_x = target_cam

      # Feed the 64-column map ring a little every frame instead of
      # rebuilding the whole window at once.
      update_map_window(cols, cam_x)
      scroll_x = cam_x.to_i % WINDOW_PX
      LR.scroll(0, scroll_x, SCROLL_Y)
      LR.scroll(1, (cam_x * BG_PARALLAX).to_i, 0)

      draw_objects(objects, cam_x, SCROLL_Y)
      LR.obj(0, px - cam_x, py - SCROLL_Y, 16, CHARSZ, CHARSZ, 1, 2)

      # 1 tile (8x8) = 1 m, like the BASIC version.  POS is the world
      # column, so it also shows how far the player has moved into the stage.
      pos_m = (px / TILE).to_i
      goal_m = COLS - 4
      if $stage != $hud_stage || $score != $hud_score || $lives != $hud_lives ||
         pos_m != $hud_pos
        # Use the whole top text row as a status bar: stage at the left,
        # score in the middle, lives and distance at the right.  Bold +
        # underline make the bar read like an old game console.
        hud = " STAGE #{$stage+1}/#{STAGES}".ljust(18)
        hud += "SCORE #{$score}".ljust(30)
        hud += "LIVES #{$lives}".ljust(10)
        hud += "POS #{pos_m}m".ljust(11)
        hud += "GOAL #{goal_m}m".ljust(11)
        hud = hud[0, 80].ljust(80)
        M.text_put(0, 0, hud,
          M.tattr(M::TEXT_BRIGHT_WHITE, M::TEXT_BLUE,
                  M::TEXT_BOLD | M::TEXT_UNDERLINE))
        $hud_stage = $stage
        $hud_score = $score
        $hud_lives = $lives
        $hud_pos = pos_m
      end

      if DEBUG
        M.text_put(0, 26,
          format("px=%-5d py=%-5d cam=%-5d base=%-4d sx=%-4d",
                 px.to_i, py.to_i, cam_x.to_i, $base, scroll_x.to_i),
          M.tattr(M::TEXT_BRIGHT_YELLOW, M::TEXT_BLACK, TA))
      end
    end

  elsif $state == :dead
    $last_ms = nil
    $acc = 0.0
    $combo = 0
    $popups.clear
    M.vsync(30)
    rx, ry = find_respawn(cols, objects, px)
    px = rx
    py = ry
    vx = 0.0; vy = 0.0
    jump_dy = nil
    jump_i = 0
    jump_n = 0
    on_ground = true
    $state = :play
  elsif $state == :clear
    $last_ms = nil
    $acc = 0.0
    M.text_put(0, 12, "  STAGE CLEAR!  ",
      M.tattr(M::TEXT_BRIGHT_YELLOW, M::TEXT_BLACK, M::TEXT_BOLD))
    M.vsync(90)
    M.text_clear(M::TEXT_CLEAR)
    if $stage >= STAGES - 1
      # last stage: show the all-clear message, then loop back to stage 1
      $state = :allclear
    else
      $stage += 1
      $combo = 0
      $popups.clear
      cols, objects = load_stage($stage, cols)
      px = 32.0
      py = GROUND_ROW * TILE - CHARSZ
      vx = 0.0; vy = 0.0
      on_ground = false
      jump_dy = nil
      $state = :play
    end
  elsif $state == :allclear
    $last_ms = nil
    $acc = 0.0
    M.text_put(0, 12, "  ALL STAGES CLEAR!  ",
      M.tattr(M::TEXT_BRIGHT_YELLOW, M::TEXT_BLACK, M::TEXT_BOLD))
    M.vsync(120)
    M.text_clear(M::TEXT_CLEAR)
    $stage = 0
    $combo = 0
    $popups.clear
    cols, objects = load_stage($stage, cols)
    px = 32.0
    py = GROUND_ROW * TILE - CHARSZ
    vx = 0.0; vy = 0.0
    on_ground = false
    jump_dy = nil
    $state = :play
  elsif $state == :gameover
    $last_ms = nil
    $acc = 0.0
    msg = "  GAME OVER  SCORE #{$score}  "
    M.text_put(0, 12, msg,
      M.tattr(M::TEXT_BRIGHT_WHITE, M::TEXT_RED, M::TEXT_BOLD))
    M.vsync(120)
    break
  end
end

music_stop
LR.clear
Sound.stop
puts "bye"