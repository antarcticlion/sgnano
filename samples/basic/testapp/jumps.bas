' jumps.bas - faithful SG BASIC port of jumps.rb (2026-11-11)
' Screen mode 5 (text + lowres 320x240), 3 stages x 16 screens,
' 640x64 tile map, 32x32 player, parallax background, score popups.
' Keys: Left/Right move, Space/Up jump, ESC/q quit. Pad 0: dir + A.
' BGM: WTF4CH.mid through Sound (SMF sequencer), as in jumps.rb.

SCREEN_W = 320: SCREEN_H = 240
TILE = 8: MAP_W = 64: MAP_H = 64
CHARSZ = 32
COLS = 640
ROWS = 64
STAGES = 3
GROUND_ROW = 56
SCROLL_Y = (GROUND_ROW - 24) * TILE
MAP_ROW0 = SCROLL_Y / TILE
MAP_ROW1 = (SCROLL_Y + SCREEN_H - 1) / TILE
SCREEN_PX = SCREEN_W
STAGE_PX = 16 * SCREEN_PX
WINDOW_PX = MAP_W * TILE
MAP_MASK = MAP_W - 1
BG_PARALLAX = 0.25
BG_ROWS = 30
BG_GROUND_Y = 26 * TILE
GRAVITY = 0.55
MOVE_V = 2.2
MAX_FALL = 7.0
JUMP_STEPS = 34
JUMP_H = 61.5
BOUNCE_STEPS = 21
BOUNCE_H = 30.1
COIN_PTS = 200
STOMP_PTS = 400
GOAL_PTS = 10000
COMBO_MAX = 8
POPUP_MS = 1000
SKY_GRADIENT_MID = 0.55
SKY_GRADIENT_LINES = (GROUND_ROW * TILE - SCROLL_Y) * 2
DISPLAY_LINES = SCREEN_H * 2
STAGE3_SAFE_HALF = 16

C_SKY = 1: C_GROUND = 2: C_BRICK = 3: C_COIN = 4: C_ENEMY = 5
C_PLAYER = 6: C_GOAL = 7: C_MTN_FAR = 8: C_MTN_NEAR = 9
C_CLOUD = 10: C_CLOUD_SH = 11: C_PIT = 12
C_GROUND_DK = 13: C_GROUND_LT = 14
C_TRANS = 128

DIM COLS(639, 63)
DIM SURF(639)
DIM OT(255), OX(255), OY(255), OA(255)
DIM PUPX(7), PUPY(7), PUPV(7), PUPT(7)
DIM JUMP_DY(33), BOUNCE_DY(20)
DIM FARH(511), NEARH(511)
DIM DIGIT$(9, 7)
DIM BGROW$(15)
DIM BGMAP(4, 2)
DIM SKY0(2), SKY1(2), SKY2(2)
DIM BGC(5, 2)

' ---- helpers ----
FUNCTION DS(BYVAL V) AS STRING
    S$ = STR$(V)
    IF LEFT$(S$, 1) = " " THEN S$ = MID$(S$, 2)
    DS = S$
END FUNCTION

FUNCTION LJ(BYVAL S$, BYVAL N) AS STRING
    IF LEN(S$) > N THEN LJ = LEFT$(S$, N) ELSE LJ = S$ + SPACE$(N - LEN(S$))
END FUNCTION

FUNCTION CLAMP(BYVAL V, BYVAL LO, BYVAL HI)
    CLAMP = V
    IF V < LO THEN CLAMP = LO
    IF V > HI THEN CLAMP = HI
END FUNCTION

FUNCTION TOPROW(BYVAL CX)
    TOPROW = ROWS
    FOR MY = 0 TO ROWS - 1
        IF COLS(CX, MY) <> 0 THEN TOPROW = MY: EXIT FUNCTION
    NEXT MY
END FUNCTION

FUNCTION SOLIDAT(BYVAL WX, BYVAL WY)
    CX = INT(WX / TILE): CY = INT(WY / TILE)
    SOLIDAT = 0
    IF CX < 0 OR CX >= COLS OR CY < 0 OR CY >= ROWS THEN EXIT FUNCTION
    IF COLS(CX, CY) = 1 OR COLS(CX, CY) = 2 THEN SOLIDAT = -1
END FUNCTION

FUNCTION BODYCLEAR(BYVAL X, BYVAL Y)
    CX = INT(X / TILE): CY = INT(Y / TILE)
    BODYCLEAR = 0
    FOR DY = 0 TO 3
        FOR DX = 0 TO 3
            IF CX + DX < 0 OR CX + DX >= COLS OR CY + DY < 0 OR CY + DY >= ROWS THEN EXIT FUNCTION
            IF COLS(CX + DX, CY + DY) <> 0 THEN EXIT FUNCTION
        NEXT DX
    NEXT DY
    BODYCLEAR = -1
END FUNCTION

FUNCTION RESPAWNY(BYVAL X)
    CX = INT(X / TILE)
    R = SURF(CX)
    RESPAWNY = -1
    IF R >= ROWS THEN EXIT FUNCTION
    IF SURF(CX + 1) <> R OR SURF(CX + 2) <> R OR SURF(CX + 3) <> R THEN EXIT FUNCTION
    Y = R * TILE - CHARSZ
    IF BODYCLEAR(X, Y) THEN RESPAWNY = Y
END FUNCTION

FUNCTION ENEMY_GAP(BYVAL X, BYVAL N)
    GAP = 9999
    FOR I = 0 TO N - 1
        IF OT(I) = 4 AND OA(I) THEN EX = OX(I): IF EX + 8 <= X THEN G = X - (EX + 8) ELSE IF EX >= X + CHARSZ THEN G = EX - (X + CHARSZ) ELSE G = 0: IF G < GAP THEN GAP = G
    NEXT I
    ENEMY_GAP = GAP
END FUNCTION

' FUNCTION の中はローカル変数の世界なので、キーの残りフレームは引数で渡す
FUNCTION READDIR(BYVAL KLEFT, BYVAL KRIGHT)
    DX = 0
    IF Machine.KeyDown(Machine.KEY_LEFT) OR KLEFT > 0 THEN DX = -1
    IF Machine.KeyDown(Machine.KEY_RIGHT) OR KRIGHT > 0 THEN DX = 1
    PD = Machine.PadDirX(0)
    IF PD <> 0 THEN DX = PD
    READDIR = DX
END FUNCTION

' 押しっぱなしでは跳ばない（着地のたびの自動再ジャンプを防ぐ）。
' USB キーボードの押下は PHYSSTEP で立ち上がりだけを見る。
FUNCTION KBJUMP(BYVAL KUP)
    KBJUMP = 0
    IF KUP > 0 THEN KBJUMP = -1
END FUNCTION

FUNCTION MOVEX(BYVAL PX, BYVAL PY, BYVAL VX)
    NX = PX + VX
    IF VX > 0 THEN RX = NX + CHARSZ - 1: IF SOLIDAT(RX, PY + 4) OR SOLIDAT(RX, PY + CHARSZ - 4) THEN NX = INT(RX / TILE) * TILE - CHARSZ
    IF VX < 0 THEN IF SOLIDAT(NX, PY + 4) OR SOLIDAT(NX, PY + CHARSZ - 4) THEN NX = (INT(NX / TILE) + 1) * TILE
    MOVEX = NX
END FUNCTION

' ---- sound ----
SUB SE(BYVAL F, BYVAL MS, BYVAL WAVE, BYVAL NOISE)
    IF SEOFF > 0 THEN EXIT SUB
    Sound.Reserve 0, -1
    IF NOISE THEN Sound.SetMode 0, 3 ELSE Sound.SetMode 0, 0: Sound.Wave 0, WAVE
    Sound.NoteOn 0, 69, 110
    Sound.Freq 0, F
    SEOFF = Machine.Ms + MS
END SUB

SUB SEPOLL
    IF SEOFF > 0 AND Machine.Ms >= SEOFF THEN Sound.NoteOff 0: Sound.SetMode 0, 0: Sound.Reserve 0, 0: SEOFF = 0
END SUB

' ---- lowres patterns and palettes ----
SUB SOLIDPAT(BYVAL TILE, BYVAL C)
    Machine.LrPattern TILE, STRING$(64, C)
END SUB

SUB GROUNDPAT
    D$ = ""
    FOR Y = 0 TO 7
        FOR X = 0 TO 7
            C = C_GROUND
            IF Y = 0 THEN C = C_GROUND_LT
            IF Y = 7 THEN C = C_GROUND_DK
            IF X = 0 THEN C = C_GROUND_DK
            IF (X = 3 AND Y = 2) OR (X = 6 AND Y = 4) THEN C = C_GROUND_DK
            IF (X = 2 AND Y = 5) OR (X = 5 AND Y = 3) THEN C = C_GROUND_LT
            D$ = D$ + CHR$(C)
        NEXT X
    NEXT Y
    Machine.LrPattern 1, D$
END SUB

SUB PATINIT
    Machine.LrPattern 0, STRING$(64, C_TRANS)
    GROUNDPAT
    SOLIDPAT 2, C_BRICK
    SOLIDPAT 3, C_COIN
    SOLIDPAT 4, C_ENEMY
    SOLIDPAT 5, C_GOAL
    SOLIDPAT 6, C_SKY
    SOLIDPAT 7, C_PIT
    ' 32x32 player: a 1024-byte row-major pattern at tile 16 (Ruby's pl.pack).
    ' A 32-pixel-wide object reads 32 contiguous bytes per line, not 4x4 tiles.
    ' BASIC strings hold at most 255 bytes, so write 4 rows (128 bytes) at a time.
    FOR K = 0 TO 7
        D$ = ""
        FOR Y = K * 4 TO K * 4 + 3
            FOR X = 0 TO CHARSZ - 1
                C = C_TRANS
                IF X >= 4 AND X < 28 AND Y >= 4 AND Y < 28 THEN C = C_PLAYER
                IF Y >= 10 AND Y < 14 AND ((X >= 10 AND X < 14) OR (X >= 18 AND X < 22)) THEN C = 0
                D$ = D$ + CHR$(C)
            NEXT X
        NEXT Y
        Machine.LrPattern 16 + K * 2, D$
    NEXT K
    ' digits 0..9 at 32..41
    FOR D = 0 TO 9
        D$ = ""
        FOR Y = 0 TO 7
            FOR X = 0 TO 7
                C = C_TRANS
                IF Y < 7 AND X < 3 AND MID$(DIGIT$(D, Y), X + 1, 1) = "#" THEN C = C_COIN
                D$ = D$ + CHR$(C)
            NEXT X
        NEXT Y
        Machine.LrPattern 32 + D, D$
    NEXT D
    ' palettes 0 and 1: the same default colours
    FOR P = 0 TO 1
        Machine.LrPalette P, C_SKY, 90, 160, 230
        Machine.LrPalette P, C_GROUND, 90, 70, 40
        Machine.LrPalette P, C_BRICK, 180, 110, 60
        Machine.LrPalette P, C_COIN, 250, 220, 40
        Machine.LrPalette P, C_ENEMY, 200, 40, 40
        Machine.LrPalette P, C_PLAYER, 240, 240, 250
        Machine.LrPalette P, C_GOAL, 40, 220, 120
        Machine.LrPalette P, C_MTN_FAR, 130, 160, 198
        Machine.LrPalette P, C_MTN_NEAR, 84, 124, 112
        Machine.LrPalette P, C_CLOUD, 248, 250, 255
        Machine.LrPalette P, C_CLOUD_SH, 198, 216, 240
        Machine.LrPalette P, C_PIT, 24, 22, 32
        Machine.LrPalette P, C_GROUND_DK, 64, 48, 28
        Machine.LrPalette P, C_GROUND_LT, 120, 98, 60
    NEXT P
END SUB

' ---- digit glyphs (0 is 3x5 on the same baseline; the two top rows are blank) ----
DATA "","","###","#.#","#.#","#.#","###"
DATA "..#",".##","..#","..#","..#","..#","..#"
DATA "###","..#","..#","###","#..","#..","###"
DATA "###","..#","..#","###","..#","..#","###"
DATA "#.#","#.#","#.#","###","..#","..#","..#"
DATA "###","#..","#..","###","..#","..#","###"
DATA "###","#..","#..","###","#.#","#.#","###"
DATA "###","..#","..#","..#","..#","..#","..#"
DATA "###","#.#","#.#","###","#.#","#.#","###"
DATA "###","#.#","#.#","###","..#","..#","###"

' ---- background layer (BG1) ----
SUB BGSPRITE(BYVAL NROWS)
    W = LEN(BGROW$(0)): H = NROWS
    BGTW = (W + 7) / 8: BGTH = (H + 7) / 8
    FOR TY = 0 TO BGTH - 1
        FOR TX = 0 TO BGTW - 1
            BUF$ = "": SKYONLY = -1
            FOR Y = 0 TO 7
                FOR X = 0 TO 7
                    YY = TY * 8 + Y: XX = TX * 8 + X
                    CH$ = "."
                    IF YY < H AND XX < W THEN CH$ = MID$(BGROW$(YY), XX + 1, 1)
                    C = C_TRANS
                    IF CH$ = "#" THEN C = C_CLOUD: SKYONLY = 0
                    IF CH$ = "+" THEN C = C_CLOUD_SH: SKYONLY = 0
                    BUF$ = BUF$ + CHR$(C)
                NEXT X
            NEXT Y
            IF SKYONLY THEN BGMAP(TX, TY) = -1 ELSE T = BGNEXT: BGNEXT = BGNEXT + 1: Machine.LrPattern T, BUF$: BGMAP(TX, TY) = T
        NEXT TX
    NEXT TY
END SUB

SUB BGSTAMP(BYVAL TX, BYVAL ROW, BYVAL FLIP)
    FOR SY = 0 TO BGTH - 1
        FOR SX = 0 TO BGTW - 1
            T = BGMAP(SX, SY)
            IF T >= 0 THEN IF FLIP THEN Machine.LrMap 1, TX + BGTW - 1 - SX, ROW + SY, T, 0, -1 ELSE Machine.LrMap 1, TX + SX, ROW + SY, T, 0
        NEXT SX
    NEXT SY
END SUB

SUB BUILDBACKGROUND
    BGNEXT = 64                 ' tiles 0..63 are the game's own (jumps.rb: BG_TILE_BASE)
    SOLIDPAT 49, C_MTN_FAR
    SOLIDPAT 50, C_MTN_NEAR
    FOR R = 0 TO BG_ROWS - 1
        FOR C = 0 TO 63: Machine.LrMap 1, C, R, 0, 0: NEXT C
    NEXT R
    PI = 3.14159265
    FOR X = 0 TO 511
        A = 2 * PI * X / 512
        FARH(X) = INT(46 + 18 * SIN(A * 2 + 0.7) + 7 * SIN(A * 5 + 2.1))
        NEARH(X) = INT(62 + 22 * SIN(A * 3 + 2.4) + 9 * SIN(A * 7 + 0.4))
    NEXT X
    FOR TX = 0 TO 63
        TOP_Y = BG_GROUND_Y
        FOR DX = 0 TO 7
            X = TX * 8 + DX
            T = BG_GROUND_Y - FARH(X): IF T < TOP_Y THEN TOP_Y = T
            T = BG_GROUND_Y - NEARH(X): IF T < TOP_Y THEN TOP_Y = T
        NEXT DX
        ROW = INT(TOP_Y / TILE): IF ROW < 0 THEN ROW = 0
        WHILE ROW <= INT(BG_GROUND_Y / TILE)
            Y0 = ROW * TILE: BUF$ = "": ALLSKY = -1: ALLFAR = -1: ALLNEAR = -1
            FOR DY = 0 TO 7
                FOR DX = 0 TO 7
                    X = TX * 8 + DX: Y = Y0 + DY
                    IF Y >= BG_GROUND_Y - NEARH(X) THEN C = C_MTN_NEAR: ALLSKY = 0: ALLFAR = 0 ELSE IF Y >= BG_GROUND_Y - FARH(X) THEN C = C_MTN_FAR: ALLSKY = 0: ALLNEAR = 0 ELSE C = C_TRANS: ALLFAR = 0: ALLNEAR = 0
                    BUF$ = BUF$ + CHR$(C)
                NEXT DX
            NEXT DY
            IF NOT ALLSKY AND ALLNEAR THEN Machine.LrMap 1, TX, ROW, 50, 0
            IF NOT ALLSKY AND NOT ALLNEAR AND ALLFAR THEN Machine.LrMap 1, TX, ROW, 49, 0
            IF NOT ALLSKY AND NOT ALLNEAR AND NOT ALLFAR THEN T = BGNEXT: BGNEXT = BGNEXT + 1: Machine.LrPattern T, BUF$: Machine.LrMap 1, TX, ROW, T, 0
            ROW = ROW + 1
        WEND
    NEXT TX
    ' the big and small clouds (the same shapes as jumps.rb)
    BGROW$(0) = "........................"
    BGROW$(1) = "..........####.........."
    BGROW$(2) = "........########........"
    BGROW$(3) = "......############......"
    BGROW$(4) = ".....##############....."
    BGROW$(5) = "....################...."
    BGROW$(6) = "...##################..."
    BGROW$(7) = "..####################.."
    BGROW$(8) = "..####################.."
    BGROW$(9) = "...##################..."
    BGROW$(10) = "....################...."
    BGROW$(11) = ".....##############....."
    BGROW$(12) = "......++++++++++++......"
    BGROW$(13) = "........................"
    BGROW$(14) = "........................"
    BGROW$(15) = "........................"
    BGSPRITE 16: BGSTAMP 2, 2, 0
    BGROW$(0) = "................"
    BGROW$(1) = "....########...."
    BGROW$(2) = "..############.."
    BGROW$(3) = ".##############."
    BGROW$(4) = "################"
    BGROW$(5) = ".++++++++++++++."
    BGROW$(6) = "................"
    BGROW$(7) = "................"
    BGSPRITE 8: BGSTAMP 10, 6, -1
    BGROW$(0) = "........................"
    BGROW$(1) = "..........####.........."
    BGROW$(2) = "........########........"
    BGROW$(3) = "......############......"
    BGROW$(4) = ".....##############....."
    BGROW$(5) = "....################...."
    BGROW$(6) = "...##################..."
    BGROW$(7) = "..####################.."
    BGROW$(8) = "..####################.."
    BGROW$(9) = "...##################..."
    BGROW$(10) = "....################...."
    BGROW$(11) = ".....##############....."
    BGROW$(12) = "......++++++++++++......"
    BGROW$(13) = "........................"
    BGROW$(14) = "........................"
    BGROW$(15) = "........................"
    BGSPRITE 16: BGSTAMP 19, 3, -1
    BGROW$(0) = "................"
    BGROW$(1) = "....########...."
    BGROW$(2) = "..############.."
    BGROW$(3) = ".##############."
    BGROW$(4) = "################"
    BGROW$(5) = ".++++++++++++++."
    BGROW$(6) = "................"
    BGROW$(7) = "................"
    BGSPRITE 8: BGSTAMP 29, 7, 0
    BGROW$(0) = "........................"
    BGROW$(1) = "..........####.........."
    BGROW$(2) = "........########........"
    BGROW$(3) = "......############......"
    BGROW$(4) = ".....##############....."
    BGROW$(5) = "....################...."
    BGROW$(6) = "...##################..."
    BGROW$(7) = "..####################.."
    BGROW$(8) = "..####################.."
    BGROW$(9) = "...##################..."
    BGROW$(10) = "....################...."
    BGROW$(11) = ".....##############....."
    BGROW$(12) = "......++++++++++++......"
    BGROW$(13) = "........................"
    BGROW$(14) = "........................"
    BGROW$(15) = "........................"
    BGSPRITE 16: BGSTAMP 37, 1, 0
    BGROW$(0) = "................"
    BGROW$(1) = "....########...."
    BGROW$(2) = "..############.."
    BGROW$(3) = ".##############."
    BGROW$(4) = "################"
    BGROW$(5) = ".++++++++++++++."
    BGROW$(6) = "................"
    BGROW$(7) = "................"
    BGSPRITE 8: BGSTAMP 47, 5, -1
    BGROW$(0) = "........................"
    BGROW$(1) = "..........####.........."
    BGROW$(2) = "........########........"
    BGROW$(3) = "......############......"
    BGROW$(4) = ".....##############....."
    BGROW$(5) = "....################...."
    BGROW$(6) = "...##################..."
    BGROW$(7) = "..####################.."
    BGROW$(8) = "..####################.."
    BGROW$(9) = "...##################..."
    BGROW$(10) = "....################...."
    BGROW$(11) = ".....##############....."
    BGROW$(12) = "......++++++++++++......"
    BGROW$(13) = "........................"
    BGROW$(14) = "........................"
    BGROW$(15) = "........................"
    BGSPRITE 16: BGSTAMP 54, 4, -1
END SUB

SUB APPLYBG(BYVAL ST)
    IF ST = 0 THEN BGC(0,0)=96: BGC(0,1)=168: BGC(0,2)=236
    IF ST = 0 THEN BGC(1,0)=130: BGC(1,1)=160: BGC(1,2)=198
    IF ST = 0 THEN BGC(2,0)=84: BGC(2,1)=124: BGC(2,2)=112
    IF ST = 0 THEN BGC(3,0)=248: BGC(3,1)=250: BGC(3,2)=255
    IF ST = 0 THEN BGC(4,0)=198: BGC(4,1)=216: BGC(4,2)=240
    IF ST = 0 THEN BGC(5,0)=24: BGC(5,1)=22: BGC(5,2)=32
    IF ST = 1 THEN BGC(0,0)=72: BGC(0,1)=136: BGC(0,2)=220
    IF ST = 1 THEN BGC(1,0)=116: BGC(1,1)=152: BGC(1,2)=208
    IF ST = 1 THEN BGC(2,0)=76: BGC(2,1)=108: BGC(2,2)=160
    IF ST = 1 THEN BGC(3,0)=248: BGC(3,1)=250: BGC(3,2)=255
    IF ST = 1 THEN BGC(4,0)=206: BGC(4,1)=220: BGC(4,2)=244
    IF ST = 1 THEN BGC(5,0)=20: BGC(5,1)=20: BGC(5,2)=38
    IF ST = 2 THEN BGC(0,0)=204: BGC(0,1)=118: BGC(0,2)=86
    IF ST = 2 THEN BGC(1,0)=158: BGC(1,1)=92: BGC(1,2)=92
    IF ST = 2 THEN BGC(2,0)=104: BGC(2,1)=58: BGC(2,2)=68
    IF ST = 2 THEN BGC(3,0)=250: BGC(3,1)=220: BGC(3,2)=180
    IF ST = 2 THEN BGC(4,0)=218: BGC(4,1)=164: BGC(4,2)=130
    IF ST = 2 THEN BGC(5,0)=30: BGC(5,1)=16: BGC(5,2)=22
    Machine.LrPalette 0, C_SKY, BGC(0,0), BGC(0,1), BGC(0,2)
    Machine.LrPalette 0, C_MTN_FAR, BGC(1,0), BGC(1,1), BGC(1,2)
    Machine.LrPalette 0, C_MTN_NEAR, BGC(2,0), BGC(2,1), BGC(2,2)
    Machine.LrPalette 0, C_CLOUD, BGC(3,0), BGC(3,1), BGC(3,2)
    Machine.LrPalette 0, C_CLOUD_SH, BGC(4,0), BGC(4,1), BGC(4,2)
    Machine.LrPalette 0, C_PIT, BGC(5,0), BGC(5,1), BGC(5,2)
END SUB

SUB APPLYSKY(BYVAL ST)
    IF ST = 0 THEN SKY0(0)=40: SKY0(1)=96: SKY0(2)=200: SKY1(0)=96: SKY1(1)=168: SKY1(2)=236: SKY2(0)=184: SKY2(1)=222: SKY2(2)=248
    IF ST = 1 THEN SKY0(0)=28: SKY0(1)=74: SKY0(2)=170: SKY1(0)=72: SKY1(1)=136: SKY1(2)=220: SKY2(0)=156: SKY2(1)=204: SKY2(2)=244
    IF ST = 2 THEN SKY0(0)=32: SKY0(1)=14: SKY0(2)=48: SKY1(0)=150: SKY1(1)=60: SKY1(2)=78: SKY2(0)=246: SKY2(1)=168: SKY2(2)=104
    FOR Y = 0 TO SKY_GRADIENT_LINES - 1
        T = Y / (SKY_GRADIENT_LINES - 1)
        IF T <= SKY_GRADIENT_MID THEN C0A=SKY0(0): C0B=SKY0(1): C0C=SKY0(2): C1A=SKY1(0): C1B=SKY1(1): C1C=SKY1(2): U=T/SKY_GRADIENT_MID ELSE C0A=SKY1(0): C0B=SKY1(1): C0C=SKY1(2): C1A=SKY2(0): C1B=SKY2(1): C1C=SKY2(2): U=(T-SKY_GRADIENT_MID)/(1-SKY_GRADIENT_MID)
        U = U * U * (3 - 2 * U)
        Machine.LrBackdrop Y, INT(C0A + (C1A - C0A) * U), INT(C0B + (C1B - C0B) * U), INT(C0C + (C1C - C0C) * U)
    NEXT Y
    FOR Y = SKY_GRADIENT_LINES TO DISPLAY_LINES - 1
        Machine.LrBackdrop Y, SKY2(0), SKY2(1), SKY2(2)
    NEXT Y
END SUB

' ---- stage data ----
DIM SAFE(7)
SAFE(0)=0: SAFE(1)=88: SAFE(2)=176: SAFE(3)=250: SAFE(4)=330: SAFE(5)=414: SAFE(6)=488: SAFE(7)=568

SUB CLEARCOLS
    FOR X = 0 TO COLS - 1
        FOR Y = 0 TO ROWS - 1: COLS(X, Y) = 0: NEXT Y
    NEXT X
END SUB

SUB GROUND(BYVAL C0, BYVAL C1, BYVAL TOP)
    FOR CX = C0 TO C1 - 1
        IF CX >= 0 AND CX < COLS THEN FOR CY = TOP TO ROWS - 1: COLS(CX, CY) = 1: NEXT CY
    NEXT CX
END SUB

SUB PIT(BYVAL C0, BYVAL C1)
    FOR CX = C0 TO C1 - 1
        IF CX >= 0 AND CX < COLS THEN FOR CY = 0 TO ROWS - 1: COLS(CX, CY) = 0: NEXT CY
    NEXT CX
END SUB

SUB BRICKS(BYVAL C0, BYVAL C1, BYVAL TOP, BYVAL THICK)
    FOR CX = C0 TO C1 - 1
        IF CX >= 0 AND CX < COLS THEN FOR CY = TOP TO TOP + THICK - 1: IF CY >= 0 AND CY < ROWS THEN COLS(CX, CY) = 2: NEXT CY
    NEXT CX
END SUB

SUB ADD_OBJ(BYVAL T, BYVAL X, BYVAL Y)
    IF NOBJ < 255 THEN OT(NOBJ) = T: OX(NOBJ) = X: OY(NOBJ) = Y: OA(NOBJ) = -1: NOBJ = NOBJ + 1
END SUB

SUB COINS(BYVAL C0, BYVAL C1, BYVAL ROW, BYVAL ST)
    FOR CX = C0 TO C1 - 1 STEP ST
        IF CX >= 0 AND CX < COLS AND ROW >= 0 AND ROW < ROWS THEN ADD_OBJ 3, CX * TILE, ROW * TILE
    NEXT CX
END SUB

SUB ENEMIES(BYVAL C0, BYVAL C1, BYVAL ROW, BYVAL ST)
    FOR CX = C0 TO C1 - 1 STEP ST
        IF CX >= 0 AND CX < COLS AND ROW >= 0 AND ROW < ROWS THEN ADD_OBJ 4, CX * TILE, ROW * TILE
    NEXT CX
END SUB

SUB COINS_AUTO(BYVAL C0, BYVAL C1, BYVAL ST, BYVAL ABOVE)
    FOR CX = C0 TO C1 - 1 STEP ST
        TOP = TOPROW(CX): ROW = TOP - ABOVE
        IF TOP < ROWS AND ROW >= 0 THEN ADD_OBJ 3, CX * TILE, ROW * TILE
    NEXT CX
END SUB

SUB ENEMIES_AUTO(BYVAL C0, BYVAL C1, BYVAL ST)
    FOR CX = C0 TO C1 - 1 STEP ST
        TOP = TOPROW(CX)
        IF TOP > 0 AND TOP < ROWS THEN ADD_OBJ 4, CX * TILE, (TOP - 1) * TILE
    NEXT CX
END SUB

FUNCTION INPOCKET(BYVAL CX)
    INPOCKET = 0
    FOR K = 0 TO 7
        IF ABS(CX - SAFE(K)) <= STAGE3_SAFE_HALF THEN INPOCKET = -1: EXIT FUNCTION
    NEXT K
END FUNCTION

SUB CLEARPOCKETS
    J = 0
    FOR I = 0 TO NOBJ - 1
        KEEP = -1
        IF OT(I) = 4 THEN IF INPOCKET(INT(OX(I) / TILE)) THEN KEEP = 0
        IF KEEP THEN OT(J) = OT(I): OX(J) = OX(I): OY(J) = OY(I): OA(J) = OA(I): J = J + 1
    NEXT I
    NOBJ = J
END SUB

SUB DEDUP
    FOR I = 0 TO NOBJ - 1
        IF OA(I) THEN FOR J = I + 1 TO NOBJ - 1: IF OA(J) AND OT(I) = OT(J) AND OX(I) = OX(J) AND OY(I) = OY(J) THEN OA(J) = 0: NEXT J
    NEXT I
    J = 0
    FOR I = 0 TO NOBJ - 1
        IF OA(I) THEN OT(J) = OT(I): OX(J) = OX(I): OY(J) = OY(I): OA(J) = -1: J = J + 1
    NEXT I
    NOBJ = J
END SUB

' Objects are static; sort them by X once so the frame loops only visit the
' visible window instead of all ~150 objects.
SUB SORT_OBJECTS
    FOR I = 1 TO NOBJ - 1
        QT = OT(I): QX = OX(I): QY = OY(I): QA = OA(I): J = I - 1: SDONE = 0
        WHILE J >= 0 AND NOT SDONE
            IF OX(J) > QX THEN OT(J + 1) = OT(J): OX(J + 1) = OX(J): OY(J + 1) = OY(J): OA(J + 1) = OA(J): J = J - 1 ELSE SDONE = -1
        WEND
        OT(J + 1) = QT: OX(J + 1) = QX: OY(J + 1) = QY: OA(J + 1) = QA
    NEXT I
END SUB

SUB COMPUTESURF
    FOR CX = 0 TO COLS - 1
        SURF(CX) = ROWS: R = ROWS - 1: FOUND = 0
        WHILE R >= 0 AND NOT FOUND
            IF COLS(CX, R) <> 0 THEN IF R = 0 THEN SURF(CX) = R: FOUND = -1 ELSE IF COLS(CX, R - 1) = 0 THEN SURF(CX) = R: FOUND = -1
            R = R - 1
        WEND
    NEXT CX
END SUB

SUB STAGE0
    COINS 10, 18, 55, 2
    PIT 52, 56
    COINS 52, 56, 52, 1
    COINS 64, 68, 55, 2
    ENEMIES 68, 69, 55, 1
    GROUND 88, 104, 55
    COINS 90, 102, 54, 3
    GROUND 112, 120, 54
    GROUND 120, 128, 52
    GROUND 128, 136, 50
    GROUND 136, 144, 52
    GROUND 144, 152, 54
    COINS 122, 134, 49, 4
    ENEMIES 156, 157, 55, 1
    PIT 168, 172
    BRICKS 176, 182, 52, 1
    COINS 176, 182, 50, 2
    ENEMIES 188, 189, 55, 1
    BRICKS 208, 216, 52, 1
    COINS 208, 216, 50, 2
    ENEMIES 228, 229, 55, 1
    PIT 252, 256
    PIT 264, 268
    COINS 252, 268, 52, 3
    ENEMIES 272, 273, 55, 1
    GROUND 292, 300, 54
    GROUND 300, 308, 52
    GROUND 308, 316, 50
    COINS 296, 312, 48, 4
    ENEMIES 304, 305, 51, 1
    PIT 328, 336
    BRICKS 330, 334, 53, 1
    COINS 328, 336, 51, 2
    ENEMIES 348, 349, 55, 1
    ENEMIES 360, 361, 55, 1
    ENEMIES 368, 369, 55, 1
    COINS 360, 370, 54, 2
    GROUND 380, 396, 52
    COINS 382, 394, 50, 4
    ENEMIES_AUTO 386, 387, 1
    PIT 412, 418
    COINS 412, 418, 52, 1
    ENEMIES 428, 429, 55, 1
    PIT 448, 472
    BRICKS 446, 454, 52, 1
    BRICKS 458, 466, 52, 1
    BRICKS 470, 478, 52, 1
    COINS 448, 472, 50, 2
    ENEMIES 458, 459, 51, 1
    ENEMIES 470, 471, 51, 1
    PIT 488, 492
    PIT 500, 504
    PIT 512, 516
    COINS 488, 516, 52, 4
    ENEMIES 508, 509, 55, 1
    GROUND 520, 528, 54
    GROUND 528, 536, 52
    GROUND 536, 544, 50
    GROUND 544, 552, 52
    COINS 528, 544, 48, 4
    ENEMIES 538, 539, 49, 1
    PIT 572, 578
    BRICKS 574, 577, 53, 1
    COINS 572, 578, 51, 2
    ENEMIES 590, 591, 55, 1
    COINS 600, 620, 55, 4
    ADD_OBJ 5, (COLS - 4) * TILE, 54 * TILE
END SUB

SUB STAGE1
    PIT 16, 21
    PIT 26, 31
    PIT 36, 41
    PIT 46, 51
    PIT 56, 61
    PIT 66, 71
    PIT 76, 81
    PIT 86, 91
    GROUND 21, 26, 54
    GROUND 31, 36, 56
    GROUND 41, 46, 54
    GROUND 51, 56, 52
    GROUND 61, 66, 54
    GROUND 71, 76, 56
    GROUND 81, 86, 54
    GROUND 91, 100, 56
    COINS_AUTO 21, 100, 3, 2
    ENEMIES 97, 98, 55, 1
    PIT 112, 117
    PIT 129, 135
    PIT 147, 153
    PIT 165, 171
    PIT 183, 189
    GROUND 117, 129, 54
    GROUND 135, 147, 52
    GROUND 153, 165, 50
    GROUND 171, 183, 52
    GROUND 189, 200, 54
    COINS_AUTO 117, 200, 4, 2
    PIT 220, 260
    BRICKS 224, 232, 52, 2
    BRICKS 236, 244, 50, 2
    BRICKS 248, 256, 53, 2
    COINS 224, 256, 48, 4
    COINS_AUTO 260, 300, 5, 2
    ENEMIES 280, 281, 55, 1
    PIT 310, 400
    GROUND 314, 319, 54
    GROUND 324, 329, 56
    GROUND 334, 339, 52
    GROUND 344, 349, 54
    GROUND 354, 359, 56
    GROUND 364, 369, 52
    GROUND 374, 379, 54
    GROUND 384, 389, 56
    GROUND 394, 399, 53
    FOR PI = 0 TO 8
        CX = 314 + PI * 10
        TOP = TOPROW(CX)
        COINS CX, CX + 1, TOP - 2, 1
    NEXT PI
    PIT 416, 422
    PIT 430, 436
    PIT 444, 450
    PIT 458, 464
    PIT 472, 478
    PIT 486, 492
    GROUND 422, 430, 54
    GROUND 436, 444, 52
    GROUND 450, 458, 50
    GROUND 464, 472, 52
    GROUND 478, 486, 54
    COINS_AUTO 422, 492, 3, 2
    ENEMIES 502, 503, 55, 1
    PIT 510, 600
    BRICKS 512, 518, 53, 2
    BRICKS 522, 528, 55, 2
    BRICKS 532, 538, 52, 2
    BRICKS 542, 548, 54, 2
    BRICKS 552, 558, 51, 2
    BRICKS 562, 568, 53, 2
    BRICKS 572, 578, 55, 2
    BRICKS 582, 588, 52, 2
    BRICKS 592, 598, 54, 2
    COINS 512, 598, 49, 6
    COINS 602, 624, 55, 4
    ENEMIES 612, 613, 55, 1
    ADD_OBJ 5, (COLS - 4) * TILE, 54 * TILE
END SUB

SUB STAGE2
    PIT 100, 104
    PIT 160, 166
    PIT 220, 224
    PIT 280, 286
    PIT 340, 344
    PIT 400, 406
    PIT 460, 464
    PIT 520, 526
    PIT 580, 584
    GROUND 40, 56, 54
    GROUND 120, 136, 54
    GROUND 180, 196, 52
    GROUND 240, 256, 54
    GROUND 300, 316, 52
    GROUND 360, 376, 54
    GROUND 420, 436, 52
    GROUND 480, 496, 54
    GROUND 540, 556, 52
    GROUND 600, 616, 54
    BRICKS 70, 78, 52, 1
    BRICKS 90, 98, 50, 1
    BRICKS 145, 153, 52, 1
    BRICKS 205, 213, 50, 1
    BRICKS 265, 273, 52, 1
    BRICKS 325, 333, 50, 1
    BRICKS 385, 393, 52, 1
    BRICKS 445, 453, 50, 1
    BRICKS 505, 513, 52, 1
    BRICKS 565, 573, 50, 1
    COINS_AUTO 0, 640, 8, 2
    ENEMIES_AUTO 20, 620, 11
    ENEMIES_AUTO 243, 279, 6
    ENEMIES_AUTO 423, 459, 6
    ENEMIES_AUTO 563, 599, 7
    CLEARPOCKETS
    COINS 620, 632, 55, 3
    ADD_OBJ 5, (COLS - 4) * TILE, 54 * TILE
END SUB

SUB BUILDSTAGE(BYVAL ST)
    CLEARCOLS
    GROUND 0, COLS, GROUND_ROW
    NOBJ = 0
    IF ST = 0 THEN STAGE0
    IF ST = 1 THEN STAGE1
    IF ST = 2 THEN STAGE2
    DEDUP
    SORT_OBJECTS
    OBJ_LO = 0
    COMPUTESURF
END SUB

' ---- lowres map ring ----
SUB FILLCOL(BYVAL WC)
    MX = WC AND 63
    FOR MY = MAP_ROW0 TO MAP_ROW1
        T = 0
        IF WC >= 0 AND WC < COLS THEN T = COLS(WC, MY)
        TT = 0
        IF T = 0 AND MY >= GROUND_ROW THEN TT = 7
        IF T = 1 THEN TT = 1
        IF T = 2 THEN TT = 2
        Machine.LrMap 0, MX, MY, TT, 0
    NEXT MY
END SUB

SUB UPDATEMAP(BYVAL CAMX)
    LFT = INT(CAMX / TILE): RGT = INT((CAMX + SCREEN_W - 1) / TILE)
    REBUILD = 0
    IF LFT < RING_LO - 1 OR RGT > RING_HI + 1 THEN REBUILD = -1
    IF REBUILD THEN FOR WC = LFT TO RGT: FILLCOL WC: NEXT WC
    IF REBUILD THEN RING_LO = LFT: RING_HI = RGT
    IF NOT REBUILD AND LFT < RING_LO THEN FILLCOL LFT: RING_LO = LFT
    IF NOT REBUILD AND RGT > RING_HI THEN FILLCOL RGT: RING_HI = RGT
    DONE = 0
    WHILE RING_HI - RING_LO + 1 > MAP_W AND NOT DONE
        IF RING_LO < LFT THEN RING_LO = RING_LO + 1 ELSE IF RING_HI > RGT THEN RING_HI = RING_HI - 1 ELSE DONE = -1
    WEND
    IF RING_HI < LFT + MAP_W - 1 THEN FILLCOL RING_HI + 1: RING_HI = RING_HI + 1: IF RING_HI - RING_LO + 1 > MAP_W THEN RING_LO = RING_LO + 1
    MAP_BASE = RING_LO
END SUB

' ---- respawn search ----
SUB TRYSPOT(BYVAL X, BYVAL NEED)
    IF DONE THEN EXIT SUB
    IF X < 0 OR X > MAX_X THEN EXIT SUB
    Y = RESPAWNY(X)
    IF Y < 0 THEN EXIT SUB
    IF ENEMY_GAP(X, NOBJ) < NEED THEN EXIT SUB
    RX = X: RY = Y: DONE = -1
END SUB

SUB FINDRESPAWN(BYVAL DEATHX)
    MAX_X = STAGE_PX - CHARSZ
    TARGET = INT(DEATHX - SCREEN_W)
    IF TARGET < 0 THEN TARGET = 0
    IF TARGET > MAX_X THEN TARGET = MAX_X
    TARGET = INT(TARGET / TILE) * TILE
    DONE = 0
    FOR NI = 0 TO 3
        NEED = 0
        IF NI = 0 THEN NEED = CHARSZ * 3
        IF NI = 1 THEN NEED = CHARSZ * 2
        IF NI = 2 THEN NEED = CHARSZ
        OFF = 0
        WHILE OFF <= STAGE_PX AND NOT DONE
            TRYSPOT TARGET - OFF, NEED
            IF OFF > 0 THEN TRYSPOT TARGET + OFF, NEED
            OFF = OFF + TILE
        WEND
    NEXT NI
    IF NOT DONE THEN RX = 32: RY = GROUND_ROW * TILE - CHARSZ
END SUB

' ---- score popups ----
FUNCTION NDIGITS(BYVAL V)
    N = 1
    WHILE V >= 10: V = INT(V / 10): N = N + 1: WEND
    NDIGITS = N
END FUNCTION

SUB ADDPOPUP(BYVAL WX, BYVAL WY, BYVAL V)
    IF PUPN >= 8 THEN FOR I = 0 TO 6: PUPX(I) = PUPX(I + 1): PUPY(I) = PUPY(I + 1): PUPV(I) = PUPV(I + 1): PUPT(I) = PUPT(I + 1): NEXT I: PUPN = 7
    PUPX(PUPN) = WX: PUPY(PUPN) = WY: PUPV(PUPN) = V: PUPT(PUPN) = Machine.Ms + POPUP_MS: PUPN = PUPN + 1
END SUB

SUB CLEARPOPUPS
    PUPN = 0
END SUB

SUB DRAWPOP(BYVAL I, BYVAL CAMX)
    REMAIN = PUPT(I) - Machine.Ms: AGE = POPUP_MS - REMAIN
    ND = NDIGITS(PUPV(I))
    SX = PUPX(I) - CAMX - (ND * 4) / 2
    SY = PUPY(I) - SCROLL_Y - INT(AGE / 90)
    VIS = 0
    IF SX > -32 AND SX < SCREEN_W + 16 AND SY > -16 AND SY < SCREEN_H + 16 THEN VIS = -1
    IF VIS THEN V = PUPV(I): DIV = 1: FOR K = 1 TO ND - 1: DIV = DIV * 10: NEXT K: FOR K = 0 TO ND - 1: DG = INT(V / DIV) - INT(INT(V / DIV) / 10) * 10: IF OBJN < 64 THEN Machine.LrObj OBJN, INT(SX + K * 4), INT(SY), 32 + DG, 8, 8, 1, 2: OBJN = OBJN + 1: V = V - DG * DIV: DIV = DIV / 10: NEXT K
END SUB

SUB DRAWPOPUPS(BYVAL CAMX)
    I = 0
    WHILE I < PUPN
        REMAIN = PUPT(I) - Machine.Ms
        IF REMAIN <= 0 THEN FOR J = I TO PUPN - 2: PUPX(J) = PUPX(J + 1): PUPY(J) = PUPY(J + 1): PUPV(J) = PUPV(J + 1): PUPT(J) = PUPT(J + 1): NEXT J
        IF REMAIN <= 0 THEN PUPN = PUPN - 1
        IF REMAIN > 0 THEN DRAWPOP I, CAMX: I = I + 1
    WEND
END SUB

SUB DRAWOBJECTS(BYVAL CAMX)
    OBJN = 1
    ' Sorted by X: move the window, then visit only the visible columns.
    ODONE = 0
    WHILE OBJ_LO > 0 AND NOT ODONE
        IF OX(OBJ_LO - 1) >= CAMX - CHARSZ THEN OBJ_LO = OBJ_LO - 1 ELSE ODONE = -1
    WEND
    ODONE = 0
    WHILE OBJ_LO < NOBJ AND NOT ODONE
        IF OX(OBJ_LO) < CAMX - CHARSZ THEN OBJ_LO = OBJ_LO + 1 ELSE ODONE = -1
    WEND
    I = OBJ_LO: ODONE = 0
    WHILE I < NOBJ AND NOT ODONE
        IF OX(I) > CAMX + SCREEN_W THEN ODONE = -1
        IF NOT ODONE AND OA(I) THEN SX = OX(I) - CAMX: SY = OY(I) - SCROLL_Y: IF SX >= -CHARSZ AND SX <= SCREEN_W AND SY >= -CHARSZ AND SY <= SCREEN_H AND OBJN < 40 THEN Machine.LrObj OBJN, INT(SX), INT(SY), OT(I), 8, 8, 1, 2: OBJN = OBJN + 1
        IF NOT ODONE THEN I = I + 1
    WEND
    DRAWPOPUPS CAMX
    FOR I = OBJN TO OBJ_SHOWN - 1: Machine.LrObjHide I: NEXT I
    OBJ_SHOWN = OBJN
END SUB

' ---- vertical movement ----
SUB MOVEY(BYVAL PX, BYVAL PY, BYVAL VY)
    NY = PY + VY: MONG = 0: MVY = VY
    IF VY >= 0 THEN FEET = NY + CHARSZ: IF SOLIDAT(PX + 4, FEET) OR SOLIDAT(PX + CHARSZ - 4, FEET) THEN CY = INT(FEET / TILE): NY = CY * TILE - CHARSZ: MVY = 0: MONG = -1
    IF VY < 0 THEN HEAD = NY: IF SOLIDAT(PX + 4, HEAD) OR SOLIDAT(PX + CHARSZ - 4, HEAD) THEN CY = INT(HEAD / TILE): NY = (CY + 1) * TILE: MVY = 0
    NYP = NY
END SUB

' ---- collisions ----
SUB STOMP(BYVAL I)
    OA(I) = 0
    IF COMBO < COMBO_MAX THEN COMBO = COMBO + 1
    PTS = STOMP_PTS * 2 ^ (COMBO - 1)
    SCORE = SCORE + PTS
    PY = OY(I) - CHARSZ
    ADDPOPUP PX + CHARSZ / 2, PY - 12, PTS
    JUMPING = 1: JUMP_I = 0: JUMP_N = BOUNCE_STEPS: ONG = 0: VY = BOUNCE_DY(0)
    SE 180, 70, 1, -1
    DONE = -1
END SUB

SUB HURT
    COMBO = 0: LIVES = LIVES - 1
    SE 140, 180, 2, 0
    IF LIVES <= 0 THEN STATE = 4 ELSE STATE = 1
    DONE = -1
END SUB

SUB HITENEMY(BYVAL I)
    IF VY_BEFORE > 0 AND (PY + CHARSZ - VY_BEFORE) <= OY(I) + 4 THEN STOMP I ELSE HURT
END SUB

SUB HITOBJ(BYVAL I)
    HIT = 0
    IF PX < OX(I) + 8 AND PX + CHARSZ > OX(I) AND PY < OY(I) + 8 AND PY + CHARSZ > OY(I) THEN HIT = -1
    IF HIT AND OT(I) = 3 THEN OA(I) = 0: PTS = COIN_PTS * 2 ^ COMBO: SCORE = SCORE + PTS: ADDPOPUP OX(I) + 4, OY(I) - 10, PTS: SE 1040, 90, 4, 0
    IF HIT AND OT(I) = 4 THEN HITENEMY I
    IF HIT AND OT(I) = 5 THEN COMBO = 0: SCORE = SCORE + GOAL_PTS: SE 1320, 260, 3, 0: STATE = 2: DONE = -1
END SUB

' ---- one fixed 60 Hz step ----
SUB PHYSSTEP
    DX = READDIR(KL, KR)
    IF DX <> 0 THEN VX = DX * MOVE_V ELSE VX = 0
    HELD = 0
    IF Machine.KeyDown(Machine.KEY_SPACE) OR Machine.KeyDown(Machine.KEY_UP) THEN HELD = -1
    JUMP = 0
    IF Machine.PadPressed(0, Machine.PAD_A) THEN JUMP = -1
    IF HELD AND NOT JUMP_HELD THEN JUMP = -1
    JUMP_HELD = HELD
    IF KBJUMP(KU) THEN JUMP = -1
    IF JUMP AND ONG THEN KU = 0: JUMPING = 1: JUMP_I = 0: JUMP_N = JUMP_STEPS: ONG = 0: SE 520, 60, 3, 0
    IF JUMPING THEN IF JUMP_I < JUMP_N THEN VY = JUMP_DY(JUMP_I): JUMP_I = JUMP_I + 1 ELSE JUMPING = 0: VY = MAX_FALL
    IF NOT JUMPING THEN VY = VY + GRAVITY: IF VY > MAX_FALL THEN VY = MAX_FALL
    VY_BEFORE = VY
    PX = MOVEX(PX, PY, VX)
    IF PX < 0 THEN PX = 0
    IF PX > STAGE_PX - CHARSZ THEN PX = STAGE_PX - CHARSZ
    MOVEY PX, PY, VY
    PY = NYP: VY = MVY: ONG = MONG
    IF JUMPING AND (ONG OR VY = 0) THEN JUMPING = 0
    IF ONG AND COMBO > 0 THEN COMBO = 0
    IF PY > ROWS * TILE + 64 THEN COMBO = 0: CLEARPOPUPS: LIVES = LIVES - 1: SE 140, 180, 2, 0: IF LIVES <= 0 THEN STATE = 4 ELSE STATE = 1
    DONE = 0
    I = OBJ_LO: ODONE = 0
    WHILE I < NOBJ AND NOT ODONE
        IF OX(I) > PX + CHARSZ + 8 THEN ODONE = -1
        IF NOT ODONE AND OA(I) AND NOT DONE THEN HITOBJ I
        IF NOT ODONE THEN I = I + 1
    WEND
END SUB

' ---- HUD and frame ----
SUB HUDUPDATE
    ' 1 tile (8x8) = 1 m.  POS is the world column, so a reported value maps
    ' directly to the stage data (the first floating block is around 176).
    POSM = INT(PX / TILE)
    GOALM = COLS - 4
    H$ = LJ(" STAGE " + DS(ST + 1) + "/" + DS(STAGES), 18)
    H$ = H$ + LJ("SCORE " + DS(SCORE), 30)
    H$ = H$ + LJ("LIVES " + DS(LIVES), 10)
    H$ = H$ + LJ("POS " + DS(POSM) + "m", 11)
    H$ = H$ + LJ("GOAL " + DS(GOALM) + "m", 11)
    Machine.TextPut 0, 0, LJ(H$, 80), Machine.TAttr(15, 1, Machine.TEXT_BOLD + Machine.TEXT_UNDERLINE)
    HUD_STAGE = ST: HUD_SCORE = SCORE: HUD_LIVES = LIVES: HUD_POS = POSM
END SUB

SUB DRAWWORLD
    TARGET = PX - SCREEN_W / 2
    IF TARGET < 0 THEN TARGET = 0
    IF TARGET > STAGE_PX - SCREEN_W THEN TARGET = STAGE_PX - SCREEN_W
    CAM = TARGET
    IF INT(CAM / TILE) <> LAST_TILE THEN UPDATEMAP CAM: LAST_TILE = INT(CAM / TILE)
    SX = INT(CAM) MOD WINDOW_PX
    Machine.LrScroll 0, SX, SCROLL_Y
    Machine.LrScroll 1, INT(CAM * BG_PARALLAX), 0
    DRAWOBJECTS CAM
    Machine.LrObj 0, INT(PX - CAM), INT(PY - SCROLL_Y), 16, CHARSZ, CHARSZ, 1, 2
    IF ST <> HUD_STAGE OR SCORE <> HUD_SCORE OR LIVES <> HUD_LIVES OR INT(PX / TILE) <> HUD_POS THEN HUDUPDATE
END SUB

SUB PLAYFRAME
    NOW = Machine.Ms
    IF LAST_MS = 0 THEN ACC = 16.6667 ELSE ACC = ACC + (NOW - LAST_MS)
    LAST_MS = NOW
    IF ACC > 33.3334 THEN ACC = 33.3334
    STEPS = 0
    WHILE ACC >= 16 AND STEPS < 2 AND STATE = 0
        ACC = ACC - 16.6667: STEPS = STEPS + 1
        PHYSSTEP
    WEND
    IF STATE = 0 THEN DRAWWORLD
END SUB

SUB DEADFRAME
    LAST_MS = 0: ACC = 0: COMBO = 0: CLEARPOPUPS
    Machine.VSync 30
    FINDRESPAWN PX
    PX = RX: PY = RY: VX = 0: VY = 0
    JUMPING = 0: JUMP_I = 0: JUMP_N = 0: ONG = -1
    STATE = 0
END SUB

SUB LOADSTAGE(BYVAL ST)
    APPLYBG ST: APPLYSKY ST: BUILDSTAGE ST
    MAP_BASE = 0: RING_LO = 0: RING_HI = -1: LAST_TILE = -1
    UPDATEMAP 0
    Machine.LrScroll 0, 0, SCROLL_Y
    Machine.LrScroll 1, 0, 0
    Machine.LrObjVisible -1
    Machine.LrBgVisible 0, -1: Machine.LrBgVisible 1, -1
    HUD_STAGE = -1: HUD_POS = -1
END SUB

SUB CLEARFRAME
    LAST_MS = 0: ACC = 0
    Machine.TextPut 0, 12, "  STAGE CLEAR!  ", Machine.TAttr(15, 0, Machine.TEXT_BOLD)
    Machine.VSync 90
    Machine.TextClear Machine.TEXT_CLEAR
    HUD_STAGE = -1: HUD_POS = -1
    IF ST >= STAGES - 1 THEN STATE = 3 ELSE ST = ST + 1: COMBO = 0: CLEARPOPUPS: LOADSTAGE ST: PX = 32: PY = GROUND_ROW * TILE - CHARSZ: VX = 0: VY = 0: ONG = 0: JUMPING = 0: STATE = 0
END SUB

SUB ALLCLEARFRAME
    LAST_MS = 0: ACC = 0
    Machine.TextPut 0, 12, "  ALL STAGES CLEAR!  ", Machine.TAttr(15, 0, Machine.TEXT_BOLD)
    Machine.VSync 120
    Machine.TextClear Machine.TEXT_CLEAR
    HUD_STAGE = -1: HUD_POS = -1: ST = 0: COMBO = 0: CLEARPOPUPS
    LOADSTAGE 0
    PX = 32: PY = GROUND_ROW * TILE - CHARSZ: VX = 0: VY = 0: ONG = 0: JUMPING = 0
    STATE = 0
END SUB

SUB GAMEOVERFRAME
    LAST_MS = 0: ACC = 0
    Machine.TextPut 0, 12, "  GAME OVER  SCORE " + DS(SCORE) + "  ", Machine.TAttr(15, 4, Machine.TEXT_BOLD)
    Machine.VSync 120
    QUIT = -1
END SUB


SUB MUSICSTART
    IF Sound.Play("WTF4CH.mid", -1) THEN PRINT "music: WTF4CH.mid (looped)" ELSE IF Sound.Play("A:/WTF4CH.mid", -1) THEN PRINT "music: A:/WTF4CH.mid (looped)" ELSE PRINT "music: none"
END SUB

SUB MUSICSTOP
    IF Sound.Playing THEN Sound.Stop
END SUB

' ---- main ----
FOR D = 0 TO 9
    FOR Y = 0 TO 6: READ DIGIT$(D, Y): NEXT Y
NEXT D
FOR K = 0 TO JUMP_STEPS - 1
    A = -4 * JUMP_H * K * (JUMP_STEPS - K) / (JUMP_STEPS * JUMP_STEPS)
    K1 = K + 1: B = -4 * JUMP_H * K1 * (JUMP_STEPS - K1) / (JUMP_STEPS * JUMP_STEPS)
    JUMP_DY(K) = B - A
NEXT K
FOR K = 0 TO BOUNCE_STEPS - 1
    A = -4 * BOUNCE_H * K * (BOUNCE_STEPS - K) / (BOUNCE_STEPS * BOUNCE_STEPS)
    K1 = K + 1: B = -4 * BOUNCE_H * K1 * (BOUNCE_STEPS - K1) / (BOUNCE_STEPS * BOUNCE_STEPS)
    BOUNCE_DY(K) = B - A
NEXT K

Machine.Mode = 5
Machine.TextClear Machine.TEXT_CLEAR
PATINIT
BUILDBACKGROUND
Sound.Wave 0, 3: Sound.Adsr 0, 0, 40, 60, 40: Sound.Volume 0, 100: Sound.Master 100
MUSICSTART
ST = 0: SCORE = 0: COINS = 0: LIVES = 3: COMBO = 0: STATE = 0: QUIT = 0
LAST_MS = 0: ACC = 0: OBJ_SHOWN = 1: HUD_STAGE = -1: HUD_SCORE = -1: HUD_LIVES = -1: HUD_POS = -1
PUPN = 0: SEOFF = 0
LOADSTAGE 0
PX = 32: PY = GROUND_ROW * TILE - CHARSZ: VX = 0: VY = 0: ONG = 0: JUMPING = 0: JUMP_I = 0: JUMP_N = 0: CAM = 0
KL = 0: KR = 0: KU = 0: JUMP_HELD = 0
Machine.ClearKeys

WHILE NOT QUIT
    Machine.VSync
    SEPOLL
    C = Machine.Key
    IF C = 27 OR C = 113 THEN QUIT = -1
    ' UART/コンソールのキーは押しっぱなしが無いので、10 フレームだけ覚える
    IF C = Machine.KEY_LEFT THEN KL = 10
    IF C = Machine.KEY_RIGHT THEN KR = 10
    IF C = Machine.KEY_UP OR C = Machine.KEY_SPACE THEN IF ONG THEN KU = 10
    IF STATE = 0 THEN PLAYFRAME
    IF STATE = 1 THEN DEADFRAME
    IF STATE = 2 THEN CLEARFRAME
    IF STATE = 3 THEN ALLCLEARFRAME
    IF STATE = 4 THEN GAMEOVERFRAME
    IF KL > 0 THEN KL = KL - 1
    IF KR > 0 THEN KR = KR - 1
    IF KU > 0 THEN KU = KU - 1
WEND

MUSICSTOP
Machine.LrClear
Sound.Stop
PRINT "bye"
