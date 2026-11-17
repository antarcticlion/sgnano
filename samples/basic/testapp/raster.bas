' Raster operation list demo (SG BASIC, 2026-11-14).  A full port of raster.rb / raster.py.
' Two lowres BG planes (a coarse and a fine mesh), a per-line raster list (backdrop / CLUT),
' scrolling, raster waves and the same 24 disc objects as the mode 4-6 test apps:
' 8/16/32/64 pixels, the five colour ramps, pad/A, v speed, o/O objects.
' Keys: 3/4/5/6 mode, r raster list, b BG planes, o/O objects, v speed, S scroll, q/ESC ends.
DEFDBL A-Z
PI = 3.14159265358979
TA = Machine.TEXT_BG_TRANSPARENT
Machine.Mode = 5

' ---- helpers ----
FUNCTION CLAMP(BYVAL V, BYVAL LO, BYVAL HI)
    IF V < LO THEN CLAMP = LO ELSE IF V > HI THEN CLAMP = HI ELSE CLAMP = V
END FUNCTION
FUNCTION WRAP(BYVAL V, BYVAL N)             ' V mod N for any size of V (MOD and AND are 16-bit)
    WRAP = V - INT(V / N) * N
END FUNCTION
FUNCTION C8(BYVAL V)                        ' 0..31 -> 0..255
    C8 = INT(V * 255 / 31)
END FUNCTION
FUNCTION GRADC(BYVAL BITS, BYVAL BAND, BYVAL V)   ' a step of the R, G, B, gray ramps
    IF BITS = 8 THEN GRADC = 8 + BAND * 32 + V: EXIT FUNCTION
    W = C8(V)
    IF BAND = 0 THEN GRADC = Machine.RGB(W, 0, 0) ELSE IF BAND = 1 THEN GRADC = Machine.RGB(0, W, 0) ELSE IF BAND = 2 THEN GRADC = Machine.RGB(0, 0, W) ELSE GRADC = Machine.RGB(W, W, W)
END FUNCTION

' ---- the framebuffer pattern of mode3.rb (8 bars, then R/G/B/gray ramps) ----
DIM BARR(7), BARG(7), BARB(7), BARC(7)
DATA 31, 31, 31, 31, 31, 0, 0, 31, 31, 0, 31, 0, 31, 0, 31, 31, 0, 0, 0, 0, 31, 0, 0, 0
FOR I = 0 TO 7: READ BARR(I), BARG(I), BARB(I): NEXT I
SUB DRAWPATTERN
    BITS = Machine.BitsPerPixel
    IF BITS = 16 THEN FOR I = 0 TO 7: BARC(I) = Machine.RGB(C8(BARR(I)), C8(BARG(I)), C8(BARB(I))): NEXT I: BORDER = Machine.RGB(255, 255, 255)
    IF BITS <> 16 THEN FOR I = 0 TO 7: Machine.FbPalette I, C8(BARR(I)), C8(BARG(I)), C8(BARB(I)): BARC(I) = I: NEXT I
    IF BITS = 8 THEN FOR V = 0 TO 31: Machine.FbPalette 8 + V, C8(V), 0, 0: Machine.FbPalette 40 + V, 0, C8(V), 0: Machine.FbPalette 72 + V, 0, 0, C8(V): Machine.FbPalette 104 + V, C8(V), C8(V), C8(V): NEXT V
    IF BITS = 8 THEN Machine.FbPalette 136, 255, 255, 255: BORDER = 136
    IF BITS = 4 THEN FOR I = 0 TO 7: V = C8(INT(I * 31 / 7)): Machine.FbPalette 8 + I, V, V, V: NEXT I: BORDER = 0
    FOR I = 0 TO 7: Machine.FillRect I * 80, 0, 80, 240, BARC(I): NEXT I
    IF BITS = 4 THEN FOR I = 0 TO 15: Machine.FillRect I * 40, 240, 40, 240, I: NEXT I
    IF BITS <> 4 THEN FOR BAND = 0 TO 3: FOR V = 0 TO 31: Machine.FillRect V * 20, 240 + BAND * 60, 20, 60, GRADC(BITS, BAND, V): NEXT V: NEXT BAND
    Machine.Rect 0, 0, 640, 480, BORDER
END SUB

' ---- lowres patterns ----
SUB RAMP(BYVAL PAL, BYVAL R, BYVAL G, BYVAL B)    ' colors 0..127 from dark to bright
    FOR C = 0 TO 127
        Machine.LrPalette PAL, C, INT(INT(R * 255 / 31) * C / 127), INT(INT(G * 255 / 31) * C / 127), INT(INT(B * 255 / 31) * C / 127)
    NEXT C
END SUB
SUB DISC(BYVAL TILE, BYVAL SIZE)        ' bright in the middle, darker to the edge, transparent outside
    DC = INT(SIZE / 2): RR = DC * DC
    D$ = "": DT = TILE
    FOR DI = 0 TO SIZE * SIZE - 1
        X = (DI MOD SIZE) - DC: Y = INT(DI / SIZE) - DC: DD = X * X + Y * Y
        IF DD >= RR THEN D$ = D$ + CHR$(128) ELSE D$ = D$ + CHR$(127 - INT(DD * 127 / RR))
        IF LEN(D$) = 128 THEN Machine.LrPattern DT, D$: D$ = "": DT = DT + 2
    NEXT DI
    IF LEN(D$) > 0 THEN Machine.LrPattern DT, D$
END SUB

DIM SPR(3)
SPR(0) = 340: SPR(1) = 336: SPR(2) = 320: SPR(3) = 256   ' tile of the disc for the width 8, 16, 32, 64
DIM SINT(64)
DATA 0, 12, 24, 36, 48, 59, 70, 80, 89, 98, 105, 112, 117, 121, 124, 126
DATA 127, 126, 124, 121, 117, 112, 105, 98, 89, 80, 70, 59, 48, 36, 24, 12
DATA 0, -12, -24, -36, -48, -59, -70, -80, -89, -98, -105, -112, -117, -121, -124, -126
DATA -127, -126, -124, -121, -117, -112, -105, -98, -89, -80, -70, -59, -48, -36, -24, -12
FOR I = 0 TO 63: READ SINT(I): NEXT I
SINT(64) = SINT(0)

' BG0: the coarse mesh.  The map references tile 3.  raster.rb builds a 32x32 block
' at tile 3; its first 64 bytes are the two top border rows, so tile 3 shows as a
' solid 8x8 colour-1 cell.
Machine.LrPattern 3, STRING$(64, 1)
' BG1: the fine mesh, a 1-pixel top/left line in every 8x8 tile (filled over the whole map).
D$ = ""
FOR Y = 0 TO 7
    FOR X = 0 TO 7
        IF X = 0 OR Y = 0 THEN D$ = D$ + CHR$(2) ELSE D$ = D$ + CHR$(128)
    NEXT X
NEXT Y
Machine.LrPattern 2, D$

' The raster wave table (240 bytes; a BASIC string is 255 bytes).
WAVE$ = ""
FOR I = 0 TO 239
    WAVE$ = WAVE$ + CHR$(INT(128 + 96 * SIN(2 * PI * I / 240)))
NEXT I

SUB SETUPLOWRES
    Machine.LrBgVisible 0, 0: Machine.LrBgVisible 1, 0: Machine.LrObjVisible 0   ' hidden while building
    Machine.LrClear
    Machine.LrPattern 0, STRING$(64, 128)
    ' tile 3 is the first 8x8 of the 32x32 coarse block; its two top rows are border
    Machine.LrPattern 3, STRING$(64, 1)
    D$ = ""
    FOR Y = 0 TO 7
        FOR X = 0 TO 7
            IF X = 0 OR Y = 0 THEN D$ = D$ + CHR$(2) ELSE D$ = D$ + CHR$(128)
        NEXT X
    NEXT Y
    Machine.LrPattern 2, D$
    Machine.LrFillMap 0, 0
    FOR TY = 0 TO 63
        FOR TX = 0 TO 63
            IF (TX MOD 4) = 0 AND (TY MOD 4) = 0 THEN Machine.LrMap 0, TX, TY, 3, 0
        NEXT TX
    NEXT TY
    Machine.LrFillMap 1, 2
    FOR P = 0 TO 7                            ' mesh palettes 8..15 (objects stay on 1..5)
        Machine.LrPalette 8 + P, 1, 255, 40 + P * 12, 0
        Machine.LrPalette 8 + P, 2, 0, 120 + P * 8, 255 - P * 12
        Machine.LrPalette 8 + P, 3, 240, 240, 240
    NEXT P
    ' objects: the five ramps of mode3.rb (white, green, orange, blue, red)
    RAMP 1, 31, 31, 31: RAMP 2, 8, 31, 12: RAMP 3, 31, 22, 6: RAMP 4, 10, 18, 31: RAMP 5, 31, 10, 10
    DISC 256, 64: DISC 320, 32: DISC 336, 16: DISC 340, 8
    Machine.LrBgVisible 0, -1: Machine.LrBgVisible 1, -1: Machine.LrObjVisible -1
END SUB

SUB SETUPRASTER
    Machine.LrRasterClear
    FOR Y = 0 TO 479
        A = SIN(2 * PI * Y / 240)
        Machine.LrBackdrop Y, INT(64 + 48 * A), 24, INT(128 - 64 * A)
        Machine.LrRaster 0, Y, 8 + (INT(Y / 12) MOD 8), 0, 0
        Machine.LrRaster 1, Y, 8 + (INT(Y / 6) MOD 8), 0, 0
    NEXT Y
END SUB

SUB SHOWBG
    Machine.LrBgVisible 0, (BG AND 1) <> 0
    Machine.LrBgVisible 1, (BG AND 2) <> 0
END SUB

SUB HELP(BYVAL MD)
    IF MD = 6 THEN EXIT SUB
    Machine.TextClear Machine.TEXT_CLEAR
    Machine.TextPut 1, 1, "RASTER 3-6: mode  r: list  b: BG  o/O: objects  v: speed  S: scroll  q: quit", Machine.TAttr(15, 0, TA)
END SUB

' ---- objects (the same layer as the mode 4-6 test apps) ----
OBJDEMO = 0: OBJCOUNT = 24
SUB SETUPOBJECTS(BYVAL HEAVY)
    IF HEAVY THEN N = 128 ELSE N = OBJCOUNT
    FOR I = 0 TO 127
        IF I >= N THEN Machine.LrObjHide I ELSE IF HEAVY THEN K = 3 ELSE K = I MOD 4
        IF I < N THEN W = 8 * 2 ^ K: Machine.LrObj I, 0, 0, SPR(K), W, W, 1 + I MOD 5, I MOD 3
        IF I < N AND HEAVY THEN Machine.LrObjMove I, 96 + (I MOD 8) * 4, 72 + (INT(I / 8) MOD 8) * 4
    NEXT I
    Machine.LrObjVisible -1
    IF HEAVY THEN OBJDEMO = 2 ELSE OBJDEMO = 1
END SUB
POX = 0: POY = 0
ODIV = 4: OPH = 0: OLAST = 0
SUB PADOBJECTS
    LX = Machine.PadStickX(0, "left"): LY = Machine.PadStickY(0, "left")
    IF LX <> 0 THEN VX = LX * 4 / ODIV ELSE VX = Machine.PadDirX(0) * 3 / ODIV
    IF LY <> 0 THEN VY = LY * 4 / ODIV ELSE VY = Machine.PadDirY(0) * 3 / ODIV
    POX = CLAMP(POX + VX, -150, 150): POY = CLAMP(POY + VY, -110, 110)
    IF Machine.PadPressed(0, Machine.PAD_A) THEN POX = 0: POY = 0   ' A: back to the middle
END SUB
SUB MOVEOBJECTS(BYVAL PH)
    OX = FIX(POX): OY = FIX(POY)
    FOR I = 0 TO OBJCOUNT - 1
        W = 8 * 2 ^ (I MOD 4)
        ' the phase stays fractional and SINT is interpolated (same as mode 4-6)
        A = PH * (1 + (I AND 3)) / 2 + I * 5
        B = PH * (1 + (INT(I / 4) AND 3)) / 3 + I * 11
        AI = INT(A): AF = A - AI: AI = AI - INT(AI / 64) * 64
        BI = INT(B): BF = B - BI: BI = BI - INT(BI / 64) * 64
        SA = SINT(AI) + (SINT(AI + 1) - SINT(AI)) * AF
        SB = SINT(BI) + (SINT(BI + 1) - SINT(BI)) * BF
        Machine.LrObjMove I, INT(160 - W / 2 + OX + SA * 140 / 127 + 0.5), INT(120 - W / 2 + OY + SB * 100 / 127 + 0.5)
    NEXT I
END SUB

' ---- mode / keys ----
BG = 3: RAS = -1: SCROLLON = -1
PH0 = 0: PH1 = 80: SY0 = 0: SY1 = 0: SX1 = 0
SUB STARTMODE(BYVAL MD, BYVAL RASON, BYVAL BGM)
    Machine.Mode = MD
    Machine.TextVisible = (MD <> 6)
    IF MD = 3 OR MD = 4 THEN DRAWPATTERN
    SETUPLOWRES
    OBJCOUNT = 24: OBJDEMO = 1
    POX = 0: POY = 0: OPH = 0: OLAST = Machine.Ms
    SETUPOBJECTS 0
    IF RASON THEN SETUPRASTER ELSE Machine.LrRasterClear
    BG = BGM
    SHOWBG
    HELP MD
    IF RASON THEN PRINT "raster: mode "; MD; " (raster on)" ELSE PRINT "raster: mode "; MD; " (raster off)"
END SUB

SUB KEYHANDLE(BYVAL C)
    IF C >= 51 AND C <= 54 THEN MD = C - 48: STARTMODE MD, RAS, BG: EXIT SUB
    IF C = 114 THEN RAS = NOT RAS: IF RAS THEN SETUPRASTER ELSE Machine.LrRasterClear
    IF C = 114 THEN HELP MD: EXIT SUB
    IF C = 98 THEN BG = (BG + 1) MOD 4: SHOWBG: EXIT SUB
    IF C = 111 THEN IF OBJDEMO <> 1 THEN OBJCOUNT = 24: SETUPOBJECTS 0: EXIT SUB ELSE IF OBJCOUNT >= 128 THEN OBJDEMO = 0: Machine.LrObjVisible 0: EXIT SUB ELSE OBJCOUNT = OBJCOUNT * 2: IF OBJCOUNT > 128 THEN OBJCOUNT = 128
    IF C = 111 THEN SETUPOBJECTS 0: EXIT SUB
    IF C = 79 THEN IF OBJDEMO = 2 THEN OBJDEMO = 0: Machine.LrObjVisible 0: EXIT SUB ELSE SETUPOBJECTS -1: EXIT SUB
    IF C = 118 THEN IF ODIV = 1 THEN ODIV = 4 ELSE ODIV = ODIV / 2
    IF C = 118 THEN EXIT SUB
    IF C = 83 THEN SCROLLON = NOT SCROLLON: EXIT SUB
END SUB

STARTMODE 5, RAS, BG
MD = 5
Machine.ClearKeys
QUIT = 0
WHILE NOT QUIT
    C = Machine.Key
    WHILE C >= 0 AND NOT QUIT
        IF C = 113 OR C = 27 THEN QUIT = -1
        IF NOT QUIT THEN KEYHANDLE C
        C = Machine.Key
    WEND
    IF SCROLLON THEN IF RAS THEN Machine.LrRasterWave 0, WAVE$, PH0: Machine.LrRasterWave 1, WAVE$, PH1: PH0 = (PH0 + 1) MOD 240: PH1 = (PH1 + 1) MOD 240
    IF SCROLLON THEN Machine.LrScroll 0, 0, SY0: Machine.LrScroll 1, SX1, SY1: SY0 = (SY0 + 2) MOD 512: SY1 = WRAP(SY1 - 2, 512): SX1 = WRAP(SX1 - 1, 512)
    NOW = Machine.Ms
    OPH = OPH + (NOW - OLAST) * 60 / 1000 / ODIV
    OLAST = NOW
    IF OBJCOUNT > 0 AND OBJDEMO = 1 THEN PADOBJECTS: MOVEOBJECTS OPH
    Machine.VSync
WEND
Machine.LrClear
Machine.Mode = 2
PRINT "bye"
