# Title: side-scrolling jump action (screen mode 5, 3 stages x 16 screens)
# MicroPython port of S:/testapp/jumps.rb (2026-10-30).  Lowres + text.
# Keys: Left/Right move, Space/Up jump (or pad 0: dir + A)
import math

SCREEN_W = 320
SCREEN_H = 240
TILE = 8
MAP_W = 64
MAP_H = 64
CHARSZ = 32
GRAVITY = 0.55
MOVE_V = 2.2
MAX_FALL = 7.0
JUMP_STEPS = 34
JUMP_H = 61.5
BOUNCE_STEPS = 21
BOUNCE_H = 30.1

def arc_table(height, steps):
    dy = [0.0] * steps
    for k in range(steps):
        a = -4.0 * height * k * (steps - k) / (steps * steps)
        b = -4.0 * height * (k + 1) * (steps - k - 1) / (steps * steps)
        dy[k] = b - a
    return dy

JUMP_DY = arc_table(JUMP_H, JUMP_STEPS)
BOUNCE_DY = arc_table(BOUNCE_H, BOUNCE_STEPS)
STAGES = 3
SCREENS_PER_STAGE = 16
SCREEN_PX = SCREEN_W
STAGE_PX = SCREENS_PER_STAGE * SCREEN_PX
COLS = STAGE_PX // TILE
ROWS = MAP_H
WINDOW_PX = MAP_W * TILE
MAP_MASK = MAP_W - 1
GROUND_ROW = 56
SCROLL_Y = (GROUND_ROW - 24) * TILE
MAP_ROW0 = SCROLL_Y // TILE
MAP_ROW1 = (SCROLL_Y + SCREEN_H - 1) // TILE

SONG_NAMES = ["WTF4CH.mid", "WTF4CH.MID", "WTF4CH.smf", "WTF4CH.SMF"]
SONG_DIRS = ["", "A:/"]
DEBUG = False

COIN_PTS = 200
STOMP_PTS = 400
GOAL_PTS = 10000
COMBO_MAX = 8
POPUP_MS = 1000

BG_PARALLAX = 0.25
BG_ROWS = 30
BG_GROUND_Y = 26 * TILE

STAGE_BG_COLORS = (
    ((96, 168, 236), (130, 160, 198), (84, 124, 112), (248, 250, 255), (198, 216, 240), (24, 22, 32)),
    ((72, 136, 220), (116, 152, 208), (76, 108, 160), (248, 250, 255), (206, 220, 244), (20, 20, 38)),
    ((204, 118, 86), (158, 92, 92), (104, 58, 68), (250, 220, 180), (218, 164, 130), (30, 16, 22)),
)

# The sky is a raster backdrop gradient (one colour per display line).
# Three stops: top, middle, horizon.  BG1's sky is transparent so this
# shows through; the mountains and clouds stay opaque.
STAGE_SKY_GRADIENT = (
    ((40, 96, 200), (96, 168, 236), (184, 222, 248)),
    ((28, 74, 170), (72, 136, 220), (156, 204, 244)),
    ((32, 14, 48), (150, 60, 78), (246, 168, 104)),
)
SKY_GRADIENT_MID = 0.55
SKY_GRADIENT_LINES = (GROUND_ROW * TILE - SCROLL_Y) * 2
DISPLAY_LINES = SCREEN_H * 2

STAGE3_SAFE_COLS = (0, 88, 176, 250, 330, 414, 488, 568)
STAGE3_SAFE_HALF = 16

C_SKY = 1
C_GROUND = 2
C_BRICK = 3
C_COIN = 4
C_ENEMY = 5
C_PLAYER = 6
C_GOAL = 7
C_MTN_FAR = 8
C_MTN_NEAR = 9
C_CLOUD = 10
C_CLOUD_SH = 11
C_PIT = 12
C_GROUND_DK = 13
C_GROUND_LT = 14

M.mode = 5
LR = M.lowres
C_TRANS = LR.TRANSPARENT

for pal in (0, 1):
    LR.palette(pal, C_SKY, 90, 160, 230)
    LR.palette(pal, C_GROUND, 90, 70, 40)
    LR.palette(pal, C_BRICK, 180, 110, 60)
    LR.palette(pal, C_COIN, 250, 220, 40)
    LR.palette(pal, C_ENEMY, 200, 40, 40)
    LR.palette(pal, C_PLAYER, 240, 240, 250)
    LR.palette(pal, C_GOAL, 40, 220, 120)
    LR.palette(pal, C_MTN_FAR, 130, 160, 198)
    LR.palette(pal, C_MTN_NEAR, 84, 124, 112)
    LR.palette(pal, C_CLOUD, 248, 250, 255)
    LR.palette(pal, C_CLOUD_SH, 198, 216, 240)
    LR.palette(pal, C_PIT, 24, 22, 32)
    LR.palette(pal, C_GROUND_DK, 64, 48, 28)
    LR.palette(pal, C_GROUND_LT, 120, 98, 60)

def solid_tile(color):
    return bytes([color] * 64)

def ground_tile():
    buf = []
    for y in range(8):
        for x in range(8):
            if y == 0:
                c = C_GROUND_LT
            elif y == 7 or x == 0:
                c = C_GROUND_DK
            elif (x == 3 and y == 2) or (x == 6 and y == 4):
                c = C_GROUND_DK
            elif (x == 2 and y == 5) or (x == 5 and y == 3):
                c = C_GROUND_LT
            else:
                c = C_GROUND
            buf.append(c)
    return bytes(buf)

LR.pattern(0, solid_tile(C_TRANS))
LR.pattern(1, ground_tile())
LR.pattern(2, solid_tile(C_BRICK))
LR.pattern(3, solid_tile(C_COIN))
LR.pattern(4, solid_tile(C_ENEMY))
LR.pattern(5, solid_tile(C_GOAL))
LR.pattern(6, solid_tile(C_SKY))
LR.pattern(7, solid_tile(C_PIT))

pl = []
for y in range(CHARSZ):
    for x in range(CHARSZ):
        inside = 4 <= x < 28 and 4 <= y < 28
        if inside:
            if 10 <= y < 14 and ((10 <= x < 14) or (18 <= x < 22)):
                pl.append(0)
            else:
                pl.append(C_PLAYER)
        else:
            pl.append(C_TRANS)
LR.pattern(16, bytes(pl))

DIGIT_GLYPHS = (
    ("###", "#.#", "#.#", "#.#", "###"),
    ("..#", ".##", "..#", "..#", "..#", "..#", "..#"),
    ("###", "..#", "..#", "###", "#..", "#..", "###"),
    ("###", "..#", "..#", "###", "..#", "..#", "###"),
    ("#.#", "#.#", "#.#", "###", "..#", "..#", "..#"),
    ("###", "#..", "#..", "###", "..#", "..#", "###"),
    ("###", "#..", "#..", "###", "#.#", "#.#", "###"),
    ("###", "..#", "..#", "..#", "..#", "..#", "..#"),
    ("###", "#.#", "#.#", "###", "#.#", "#.#", "###"),
    ("###", "#.#", "#.#", "###", "..#", "..#", "###"),
)
for d, rows in enumerate(DIGIT_GLYPHS):
    h = len(rows)
    top = 7 - h
    buf = []
    for y in range(8):
        for x in range(8):
            on = top <= y < top + h and x < 3 and rows[y - top][x] == "#"
            buf.append(C_COIN if on else C_TRANS)
    LR.pattern(32 + d, bytes(buf))

BG_TILE_BASE = 64
bg_next_tile = BG_TILE_BASE

def bg_sprite(rows):
    global bg_next_tile
    w = len(rows[0])
    h = len(rows)
    tw = (w + 7) // 8
    th = (h + 7) // 8
    out = []
    for ty in range(th):
        line = []
        for tx in range(tw):
            buf = []
            sky_only = True
            for y in range(8):
                for x in range(8):
                    yy = ty * 8 + y
                    xx = tx * 8 + x
                    ch = rows[yy][xx] if yy < h and xx < w else "."
                    if ch == "#":
                        buf.append(C_CLOUD)
                        sky_only = False
                    elif ch == "+":
                        buf.append(C_CLOUD_SH)
                        sky_only = False
                    else:
                        buf.append(C_TRANS)
            if sky_only:
                line.append(None)
            else:
                t = bg_next_tile
                bg_next_tile += 1
                LR.pattern(t, bytes(buf))
                line.append(t)
        out.append(line)
    return out, tw, th

def bg_stamp(sprite, tx, row, flip=False):
    map_, tw, th = sprite
    for sy in range(th):
        for sx in range(tw):
            tile = map_[sy][sx]
            if tile is not None:
                if flip:
                    LR.map(1, tx + tw - 1 - sx, row + sy, tile, 0, True, False)
                else:
                    LR.map(1, tx + sx, row + sy, tile, 0)

def build_background():
    global bg_next_tile
    sky_tile = 0
    far_tile = 49
    near_tile = 50
    LR.pattern(far_tile, solid_tile(C_MTN_FAR))
    LR.pattern(near_tile, solid_tile(C_MTN_NEAR))

    # BG1's sky is transparent so the per-line raster backdrop gradient
    # shows through.  Tile 0 is the transparent pattern built above.
    for r in range(BG_ROWS):
        for c in range(64):
            LR.map(1, c, r, sky_tile, 0)

    far_h = [0] * 512
    near_h = [0] * 512
    for x in range(512):
        a = 2.0 * math.pi * x / 512.0
        far_h[x] = int(46.0 + 18.0 * math.sin(a * 2.0 + 0.7) + 7.0 * math.sin(a * 5.0 + 2.1))
        near_h[x] = int(62.0 + 22.0 * math.sin(a * 3.0 + 2.4) + 9.0 * math.sin(a * 7.0 + 0.4))

    for tx in range(64):
        top_y = BG_GROUND_Y
        for dx in range(8):
            x = tx * 8 + dx
            t = BG_GROUND_Y - far_h[x]
            if t < top_y:
                top_y = t
            t = BG_GROUND_Y - near_h[x]
            if t < top_y:
                top_y = t
        row = top_y // TILE
        if row < 0:
            row = 0
        while row <= BG_GROUND_Y // TILE:
            y0 = row * TILE
            buf = []
            all_sky = True
            all_far = True
            all_near = True
            for dy in range(8):
                for dx in range(8):
                    x = tx * 8 + dx
                    y = y0 + dy
                    if y >= BG_GROUND_Y - near_h[x]:
                        buf.append(C_MTN_NEAR)
                        all_sky = False
                        all_far = False
                    elif y >= BG_GROUND_Y - far_h[x]:
                        buf.append(C_MTN_FAR)
                        all_sky = False
                        all_near = False
                    else:
                        buf.append(C_TRANS)
                        all_far = False
                        all_near = False
            if all_sky:
                pass
            elif all_near:
                LR.map(1, tx, row, near_tile, 0)
            elif all_far:
                LR.map(1, tx, row, far_tile, 0)
            else:
                t = bg_next_tile
                bg_next_tile += 1
                LR.pattern(t, bytes(buf))
                LR.map(1, tx, row, t, 0)
            row += 1

    big = bg_sprite((
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
        "........................",
    ))
    small = bg_sprite((
        "................",
        "....########....",
        "..############..",
        ".##############.",
        "################",
        ".++++++++++++++.",
        "................",
        "................",
    ))
    bg_stamp(big, 2, 2)
    bg_stamp(small, 10, 6, True)
    bg_stamp(big, 19, 3, True)
    bg_stamp(small, 29, 7)
    bg_stamp(big, 37, 1)
    bg_stamp(small, 47, 5, True)
    bg_stamp(big, 54, 4, True)

def apply_bg_palette(stage):
    c = STAGE_BG_COLORS[stage]
    LR.palette(0, C_SKY, c[0][0], c[0][1], c[0][2])
    LR.palette(0, C_MTN_FAR, c[1][0], c[1][1], c[1][2])
    LR.palette(0, C_MTN_NEAR, c[2][0], c[2][1], c[2][2])
    LR.palette(0, C_CLOUD, c[3][0], c[3][1], c[3][2])
    LR.palette(0, C_CLOUD_SH, c[4][0], c[4][1], c[4][2])
    LR.palette(0, C_PIT, c[5][0], c[5][1], c[5][2])

def apply_sky_gradient(stage):
    stops = STAGE_SKY_GRADIENT[stage]
    for y in range(SKY_GRADIENT_LINES):
        t = y / (SKY_GRADIENT_LINES - 1)
        if t <= SKY_GRADIENT_MID:
            c0 = stops[0]
            c1 = stops[1]
            u = t / SKY_GRADIENT_MID
        else:
            c0 = stops[1]
            c1 = stops[2]
            u = (t - SKY_GRADIENT_MID) / (1.0 - SKY_GRADIENT_MID)
        u = u * u * (3.0 - 2.0 * u)
        r = int(c0[0] + (c1[0] - c0[0]) * u)
        g = int(c0[1] + (c1[1] - c0[1]) * u)
        b = int(c0[2] + (c1[2] - c0[2]) * u)
        LR.backdrop(y, r, g, b)
    c1 = stops[2]
    for y in range(SKY_GRADIENT_LINES, DISPLAY_LINES):
        LR.backdrop(y, c1[0], c1[1], c1[2])

build_background()

Sound.wave(0, Sound.SQUARE)
Sound.adsr(0, 0, 40, 60, 40)
Sound.volume(0, 100)
Sound.master(100)
se_off_at = 0

def se_start(freq, ms, wave=Sound.SQUARE, noise=False):
    global se_off_at
    Sound.reserve(0, True)
    if noise:
        Sound.set_mode(0, Sound.NOISE_MODE)
    else:
        Sound.set_mode(0, Sound.WT)
        Sound.wave(0, wave)
    Sound.note_on(0, 69, 110)
    Sound.freq(0, freq)
    se_off_at = M.ms() + ms

def se_poll():
    global se_off_at
    if se_off_at > 0 and M.ms() >= se_off_at:
        Sound.note_off(0)
        Sound.set_mode(0, Sound.WT)
        Sound.reserve(0, False)
        se_off_at = 0

def se_jump(): se_start(520, 60, Sound.SQUARE)
def se_coin(): se_start(1040, 90, Sound.PULSE25)
def se_stomp(): se_start(180, 70, Sound.TRIANGLE, True)
def se_hurt(): se_start(140, 180, Sound.SAW)
def se_goal(): se_start(1320, 260, Sound.SQUARE)

def find_song():
    for d in SONG_DIRS:
        for name in SONG_NAMES:
            path = d + name
            if File.exist(path):
                return path
    return None

def music_start():
    path = find_song()
    if path:
        Sound.play(path, True)
        print("music: %s (%.1f s, looped)" % (path, Sound.length() / 1000.0))
    else:
        print("music: WTF4CH.mid is not in %s -- no music" % Dir.pwd())

def music_stop():
    if Sound.playing():
        Sound.stop()

def stage_ground(cols, c0, c1, top=GROUND_ROW):
    for cx in range(c0, c1):
        if 0 <= cx < COLS:
            for cy in range(top, ROWS):
                cols[cx][cy] = 1

def stage_bricks(cols, c0, c1, top, thick=1):
    for cx in range(c0, c1):
        if 0 <= cx < COLS:
            for cy in range(top, min(top + thick, ROWS)):
                if cy >= 0:
                    cols[cx][cy] = 2

def stage_pit(cols, c0, c1):
    for cx in range(c0, c1):
        if 0 <= cx < COLS:
            for cy in range(ROWS):
                cols[cx][cy] = 0

def stage_coins(objects, c0, c1, row, step=1):
    for cx in range(c0, c1, step):
        if 0 <= cx < COLS and 0 <= row < ROWS:
            objects.append([3, cx * TILE, row * TILE, True])

def stage_enemies(objects, c0, c1, row, step=1):
    for cx in range(c0, c1, step):
        if 0 <= cx < COLS and 0 <= row < ROWS:
            objects.append([4, cx * TILE, row * TILE, True])

def stage_top_row(cols, cx):
    for my in range(ROWS):
        if cols[cx][my] != 0:
            return my
    return ROWS

def stage_enemies_auto(cols, objects, c0, c1, step):
    for cx in range(c0, c1, step):
        top = stage_top_row(cols, cx)
        if 0 < top < ROWS:
            objects.append([4, cx * TILE, (top - 1) * TILE, True])

def stage_coins_auto(cols, objects, c0, c1, step, above):
    for cx in range(c0, c1, step):
        top = stage_top_row(cols, cx)
        row = top - above
        if top < ROWS and row >= 0:
            objects.append([3, cx * TILE, row * TILE, True])

def stage_clear_enemy_pockets(objects):
    keep = []
    for o in objects:
        if o[0] == 4:
            cx = int(o[1] // TILE)
            safe = False
            for sc in STAGE3_SAFE_COLS:
                if abs(cx - sc) <= STAGE3_SAFE_HALF:
                    safe = True
                    break
            if not safe:
                keep.append(o)
        else:
            keep.append(o)
    return keep

def build_stage(stage, cols=None):
    if cols is not None:
        for cx in range(COLS):
            col = cols[cx]
            for cy in range(50, GROUND_ROW):
                col[cy] = 0
    else:
        cols = [[0] * ROWS for _ in range(COLS)]
    objects = []
    stage_ground(cols, 0, COLS)
    if stage == 0:
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
        objects.append([5, (COLS - 4) * TILE, 54 * TILE, True])
    elif stage == 1:
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
        stage_pit(cols, 220, 260)
        stage_bricks(cols, 224, 232, 52, 2)
        stage_bricks(cols, 236, 244, 50, 2)
        stage_bricks(cols, 248, 256, 53, 2)
        stage_coins(objects, 224, 256, 48, 4)
        stage_coins_auto(cols, objects, 260, 300, 5, 2)
        stage_enemies(objects, 280, 281, 55)
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
        for cx in (314, 324, 334, 344, 354, 364, 374, 384, 394):
            top = stage_top_row(cols, cx)
            stage_coins(objects, cx, cx + 1, top - 2)
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
        objects.append([5, (COLS - 4) * TILE, 54 * TILE, True])
    else:
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
        stage_enemies_auto(cols, objects, 243, 279, 6)
        stage_enemies_auto(cols, objects, 423, 459, 6)
        stage_enemies_auto(cols, objects, 563, 599, 7)
        objects = stage_clear_enemy_pockets(objects)
        stage_coins(objects, 620, 632, 55, 3)
        objects.append([5, (COLS - 4) * TILE, 54 * TILE, True])
    seen = set()
    uniq = []
    for o in objects:
        key = tuple(o)
        if key not in seen:
            seen.add(key)
            uniq.append(o)
    return cols, uniq

def fill_map_column(cols, wc):
    mx = wc & MAP_MASK
    for my in range(MAP_ROW0, MAP_ROW1 + 1):
        t = cols[wc][my] if 0 <= wc < COLS else 0
        if t == 0:
            tile = 7 if my >= GROUND_ROW else 0
        elif t == 1:
            tile = 1
        elif t == 2:
            tile = 2
        else:
            tile = 0
        LR.map(0, mx, my, tile, 0)

ring_lo = 0
ring_hi = -1
base = 0

def update_map_window(cols, cam_x):
    global ring_lo, ring_hi, base
    left = int(cam_x // TILE)
    right = int((cam_x + SCREEN_W - 1) // TILE)
    if left < ring_lo - 1 or right > ring_hi + 1:
        for wc in range(left, right + 1):
            fill_map_column(cols, wc)
        ring_lo = left
        ring_hi = right
    else:
        if left < ring_lo:
            fill_map_column(cols, left)
            ring_lo = left
        if right > ring_hi:
            fill_map_column(cols, right)
            ring_hi = right
    while ring_hi - ring_lo + 1 > MAP_W:
        if ring_lo < left:
            ring_lo += 1
        elif ring_hi > right:
            ring_hi -= 1
        else:
            break
    if ring_hi < left + MAP_W - 1:
        wc = ring_hi + 1
        fill_map_column(cols, wc)
        ring_hi = wc
        if ring_hi - ring_lo + 1 > MAP_W:
            ring_lo += 1
    base = ring_lo

score = 0
stage = 0
lives = 3
combo = 0
popups = []
state = "play"
surface_row = []

def compute_surface_rows(cols):
    rows = [ROWS] * COLS
    for cx in range(COLS):
        found = ROWS
        r = ROWS - 1
        while r >= 0:
            if cols[cx][r] != 0 and (r == 0 or cols[cx][r - 1] == 0):
                found = r
                break
            r -= 1
        rows[cx] = found
    return rows

def load_stage(stage, old_cols=None):
    global surface_row, base, ring_lo, ring_hi
    apply_bg_palette(stage)
    apply_sky_gradient(stage)
    cols, objects = build_stage(stage, old_cols)
    surface_row = compute_surface_rows(cols)
    base = 0
    ring_lo = 0
    ring_hi = -1
    update_map_window(cols, 0.0)
    LR.scroll(0, 0, SCROLL_Y)
    LR.scroll(1, 0, 0)
    LR.obj_visible = True
    LR.bg_visible(0, True)
    LR.bg_visible(1, True)
    return cols, objects

music_start()

cols, objects = load_stage(stage)
px = 32.0
py = GROUND_ROW * TILE - CHARSZ
vx = 0.0
vy = 0.0
on_ground = False
jump_dy = None
jump_i = 0
jump_n = 0
cam_x = 0.0
state = "play"
M.clear_keys()
M.text_clear(M.TEXT_CLEAR)
TA = M.TEXT_BG_TRANSPARENT

def solid_at(cols, wx, wy):
    cx = int(wx // TILE)
    cy = int(wy // TILE)
    if cx < 0 or cx >= COLS or cy < 0 or cy >= ROWS:
        return False
    return cols[cx][cy] == 1 or cols[cx][cy] == 2

def respawn_body_clear(cols, x, y):
    cx = int(x // TILE)
    cy = int(y // TILE)
    for dy in range(4):
        for dx in range(4):
            if cx + dx >= COLS or cy + dy >= ROWS or cols[cx + dx][cy + dy] != 0:
                return False
    return True

def respawn_y_at(cols, x):
    cx = int(x // TILE)
    if cx < 0 or cx + 3 >= COLS:
        return None
    r = surface_row[cx]
    if r >= ROWS:
        return None
    if not (surface_row[cx + 1] == r and surface_row[cx + 2] == r and surface_row[cx + 3] == r):
        return None
    y = r * TILE - CHARSZ
    if not respawn_body_clear(cols, x, y):
        return None
    return y

def enemy_gap_x(enemies, x):
    gap = 9999
    for ex in enemies:
        if ex + 8 <= x:
            g = x - (ex + 8)
        elif ex >= x + CHARSZ:
            g = ex - (x + CHARSZ)
        else:
            g = 0
        if g < gap:
            gap = g
    return gap

def find_respawn(cols, objects, death_x):
    max_x = STAGE_PX - CHARSZ
    target = int(death_x) - SCREEN_W
    if target < 0:
        target = 0
    if target > max_x:
        target = max_x
    target = int(target // TILE) * TILE
    enemies = [o[1] for o in objects if o[0] == 4 and o[3]]
    for need in (CHARSZ * 3, CHARSZ * 2, CHARSZ, 0):
        off = 0
        while off <= STAGE_PX:
            signs = (-1,) if off == 0 else (-1, 1)
            for sign in signs:
                x = target + sign * off
                if x < 0 or x > max_x:
                    continue
                y = respawn_y_at(cols, x)
                if y is None:
                    continue
                if enemy_gap_x(enemies, x) < need:
                    continue
                return float(x), float(y)
            off += TILE
    return 32.0, float(GROUND_ROW * TILE - CHARSZ)

def add_popup(wx, wy, value):
    digits = []
    v = value
    while True:
        digits.insert(0, v % 10)
        v //= 10
        if v == 0:
            break
    popups.append([wx, wy, digits, M.ms() + POPUP_MS])
    if len(popups) > 8:
        popups.pop(0)

def draw_popups(cam_x, scroll_y, n):
    now = M.ms()
    i = 0
    while i < len(popups):
        p = popups[i]
        remain = p[3] - now
        if remain <= 0:
            popups.pop(i)
            continue
        age = POPUP_MS - remain
        digits = p[2]
        sx = p[0] - cam_x - (len(digits) * 4) // 2
        sy = p[1] - scroll_y - age // 90
        if -32 < sx < SCREEN_W + 16 and -16 < sy < SCREEN_H + 16:
            k = 0
            while k < len(digits) and n < 64:
                LR.obj(n, int(sx + k * 4), int(sy), 32 + digits[k], 8, 8, 1, 2)
                n += 1
                k += 1
        i += 1
    return n

obj_shown = 1

def draw_objects(objects, cam_x, scroll_y):
    global obj_shown
    n = 1
    for o in objects:
        typ, wx, wy, alive = o
        if not alive:
            continue
        sx = wx - cam_x
        if sx < -CHARSZ or sx > SCREEN_W:
            continue
        sy = wy - scroll_y
        if sy < -CHARSZ or sy > SCREEN_H:
            continue
        if typ == 3:
            tile = 3
        elif typ == 4:
            tile = 4
        elif typ == 5:
            tile = 5
        else:
            tile = 0
        LR.obj(n, int(sx), int(sy), tile, 8, 8, 1, 2)
        n += 1
        if n >= 40:
            break
    n = draw_popups(cam_x, scroll_y, n)
    i = n
    while i < obj_shown:
        LR.obj_hide(i)
        i += 1
    obj_shown = n

def read_dir():
    dx = 0
    if M.pad(0) is not None:
        pdir = M.pad_dir(0)
        if pdir is not None and isinstance(pdir, (list, tuple)) and isinstance(pdir[0], int):
            if pdir[0] < 0:
                dx = -1
            elif pdir[0] > 0:
                dx = 1
    if M.key_down(M.KEY_LEFT):
        dx = -1
    if M.key_down(M.KEY_RIGHT):
        dx = 1
    return dx

def pad_jump():
    if M.pad_pressed(0, M.PAD_A):
        return True
    if M.pad(0) is not None:
        pdir = M.pad_dir(0)
        if pdir is not None and isinstance(pdir, (list, tuple)) and len(pdir) > 1 and isinstance(pdir[1], int):
            if pdir[1] < 0:
                return True
    return False

def kb_jump():
    return M.key_down(M.KEY_SPACE) or M.key_down(M.KEY_UP)

def move_x(px, py, vx, cols):
    nx = px + vx
    if vx > 0:
        rx = nx + CHARSZ - 1
        if solid_at(cols, rx, py + 4) or solid_at(cols, rx, py + CHARSZ - 4):
            nx = int(rx // TILE) * TILE - CHARSZ
    elif vx < 0:
        if solid_at(cols, nx, py + 4) or solid_at(cols, nx, py + CHARSZ - 4):
            nx = (int(nx // TILE) + 1) * TILE
    return nx

def move_y(px, py, vy, cols):
    ny = py + vy
    if vy >= 0:
        feet = ny + CHARSZ
        if solid_at(cols, px + 4, feet) or solid_at(cols, px + CHARSZ - 4, feet):
            cy = int(feet // TILE)
            return cy * TILE - CHARSZ, 0.0, True
        return ny, vy, False
    head = ny
    if solid_at(cols, px + 4, head) or solid_at(cols, px + CHARSZ - 4, head):
        cy = int(head // TILE)
        return (cy + 1) * TILE, 0.0, False
    return ny, vy, False

last_ms = None
acc = 0.0
hud_stage = -1
hud_score = -1
hud_lives = -1
hud_pos = -1

while True:
    M.vsync()
    se_poll()

    if state == "play":
        now = M.ms()
        if last_ms is not None:
            acc += now - last_ms
        else:
            acc = 16.6667
        last_ms = now
        if acc > 33.3334:
            acc = 33.3334
        steps = 0
        while acc >= 16.0 and steps < 2:
            acc -= 16.6667
            steps += 1
            dx = read_dir()
            vx = dx * MOVE_V if dx != 0 else 0.0

            jump = pad_jump() or kb_jump()
            if jump and on_ground:
                jump_dy = JUMP_DY
                jump_i = 0
                jump_n = JUMP_STEPS
                on_ground = False
                se_jump()

            if jump_dy is not None:
                if jump_i < jump_n:
                    vy = jump_dy[jump_i]
                    jump_i += 1
                else:
                    jump_dy = None
                    vy = MAX_FALL
            else:
                vy += GRAVITY
                if vy > MAX_FALL:
                    vy = MAX_FALL

            vy_before = vy
            px = move_x(px, py, vx, cols)
            if px < 0:
                px = 0.0
            if px > STAGE_PX - CHARSZ:
                px = float(STAGE_PX - CHARSZ)

            py, vy, on_ground = move_y(px, py, vy, cols)
            if jump_dy is not None and (on_ground or vy == 0.0):
                jump_dy = None
            if on_ground and combo > 0:
                combo = 0

            if py > ROWS * TILE + 64:
                combo = 0
                popups.clear()
                lives -= 1
                se_hurt()
                state = "gameover" if lives <= 0 else "dead"

            for o in objects:
                if not o[3]:
                    continue
                typ, wx, wy = o[0], o[1], o[2]
                if px < wx + 8 and px + CHARSZ > wx and py < wy + 8 and py + CHARSZ > wy:
                    if typ == 3:
                        o[3] = False
                        pts = COIN_PTS << combo
                        score += pts
                        add_popup(wx + 4, wy - 10, pts)
                        se_coin()
                    elif typ == 4:
                        if vy_before > 0 and (py + CHARSZ - vy_before) <= wy + 4:
                            o[3] = False
                            if combo < COMBO_MAX:
                                combo += 1
                            pts = STOMP_PTS << (combo - 1)
                            score += pts
                            py = wy - CHARSZ
                            add_popup(px + CHARSZ // 2, py - 12, pts)
                            jump_dy = BOUNCE_DY
                            jump_i = 0
                            jump_n = BOUNCE_STEPS
                            on_ground = False
                            vy = jump_dy[0]
                            se_stomp()
                            break
                        else:
                            combo = 0
                            lives -= 1
                            se_hurt()
                            state = "gameover" if lives <= 0 else "dead"
                            break
                    elif typ == 5:
                        combo = 0
                        score += GOAL_PTS
                        se_goal()
                        state = "clear"
                        break
            if state != "play":
                break

        if state == "play":
            target_cam = px - SCREEN_W / 2
            if target_cam < 0:
                target_cam = 0.0
            if target_cam > STAGE_PX - SCREEN_W:
                target_cam = float(STAGE_PX - SCREEN_W)
            cam_x = target_cam
            update_map_window(cols, cam_x)
            scroll_x = int(cam_x) % WINDOW_PX
            LR.scroll(0, scroll_x, SCROLL_Y)
            LR.scroll(1, int(cam_x * BG_PARALLAX), 0)
            draw_objects(objects, cam_x, SCROLL_Y)
            LR.obj(0, int(px - cam_x), int(py - SCROLL_Y), 16, CHARSZ, CHARSZ, 1, 2)

            # 1 tile (8x8) = 1 m, like the BASIC version.  POS is the world
            # column, so it also shows how far the player has moved into the stage.
            pos_m = int(px // TILE)
            goal_m = COLS - 4
            if stage != hud_stage or score != hud_score or lives != hud_lives or pos_m != hud_pos:
                hud = ljust(" STAGE %d/%d" % (stage + 1, STAGES), 18)
                hud += ljust("SCORE %d" % score, 30)
                hud += ljust("LIVES %d" % lives, 10)
                hud += ljust("POS %dm" % pos_m, 11)
                hud += ljust("GOAL %dm" % goal_m, 11)
                hud = ljust(hud[:80], 80)
                M.text_put(0, 0, hud, M.tattr(M.TEXT_BRIGHT_WHITE, M.TEXT_BLUE, M.TEXT_BOLD | M.TEXT_UNDER))
                hud_stage = stage
                hud_score = score
                hud_lives = lives
                hud_pos = pos_m

            if DEBUG:
                M.text_put(0, 26, "px=%-5d py=%-5d cam=%-5d base=%-4d sx=%-4d" % (
                    int(px), int(py), int(cam_x), base, scroll_x), M.tattr(M.TEXT_BRIGHT_YELLOW, M.TEXT_BLACK, TA))

    elif state == "dead":
        last_ms = None
        acc = 0.0
        combo = 0
        popups.clear()
        M.vsync(30)
        rx, ry = find_respawn(cols, objects, px)
        px = rx
        py = ry
        vx = 0.0
        vy = 0.0
        jump_dy = None
        jump_i = 0
        jump_n = 0
        on_ground = True
        state = "play"
    elif state == "clear":
        last_ms = None
        acc = 0.0
        M.text_put(0, 12, "  STAGE CLEAR!  ", M.tattr(M.TEXT_BRIGHT_YELLOW, M.TEXT_BLACK, M.TEXT_BOLD))
        M.vsync(90)
        M.text_clear(M.TEXT_CLEAR)
        if stage >= STAGES - 1:
            state = "allclear"
        else:
            stage += 1
            combo = 0
            popups.clear()
            cols, objects = load_stage(stage, cols)
            px = 32.0
            py = float(GROUND_ROW * TILE - CHARSZ)
            vx = 0.0
            vy = 0.0
            on_ground = False
            jump_dy = None
            state = "play"
    elif state == "allclear":
        last_ms = None
        acc = 0.0
        M.text_put(0, 12, "  ALL STAGES CLEAR!  ", M.tattr(M.TEXT_BRIGHT_YELLOW, M.TEXT_BLACK, M.TEXT_BOLD))
        M.vsync(120)
        M.text_clear(M.TEXT_CLEAR)
        stage = 0
        combo = 0
        popups.clear()
        cols, objects = load_stage(stage, cols)
        px = 32.0
        py = float(GROUND_ROW * TILE - CHARSZ)
        vx = 0.0
        vy = 0.0
        on_ground = False
        jump_dy = None
        state = "play"
    elif state == "gameover":
        last_ms = None
        acc = 0.0
        msg = "  GAME OVER  SCORE %d  " % score
        M.text_put(0, 12, msg, M.tattr(M.TEXT_BRIGHT_WHITE, M.TEXT_RED, M.TEXT_BOLD))
        M.vsync(120)
        break

music_stop()
LR.clear()
Sound.stop()
print("bye")
