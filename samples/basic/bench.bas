' Speed table for docs/sgnano_basic_guide.md (2026-11-01): the same items as samples/ruby/bench.rb
' in screen mode 1 (no FB), 2 (RGB555 FB shown) and 4 (CLUT4 FB shown).
DEFDBL A-Z
SUB REPORT(BYVAL LABEL$, BYVAL T0)
    PRINT "BENCH"; Machine.Mode; " "; LABEL$; ": "; MID$(STR$(INT(Machine.Ms - T0)), 2); " ms"
END SUB
DATA 1, 2, 4
FOR MI = 1 TO 3
    READ M: Machine.Mode = M
    T0 = Machine.Ms: I = 0: WHILE I < 100000: I = I + 1: WEND: REPORT "while 100k", T0
    IF M = 1 THEN GOTO NEXTMODE
    IF M = 4 THEN C = 7 ELSE C = Machine.RGB(255, 255, 0)
    T0 = Machine.Ms: FOR I = 0 TO 9999: Machine.PSet I MOD 640, INT(I / 640) MOD 480, C: NEXT I: REPORT "pset 10k", T0
    T0 = Machine.Ms: FOR I = 0 TO 999: X = (I * 7) MOD 576: Y = (I * 5) MOD 432: Machine.FillRect X, Y, 64, 48, C: NEXT I: REPORT "fill_rect 64x48 1000", T0
    T0 = Machine.Ms: FOR I = 0 TO 999: Machine.Line 0, 0, 639, I MOD 480, C: NEXT I: REPORT "line full 1000", T0
    T0 = Machine.Ms: FOR I = 0 TO 999: X = (I * 7) MOD 576: Y = (I * 5) MOD 432: Machine.FillTriangle X, Y, X + 63, Y, X, Y + 47, C: NEXT I: REPORT "fill_triangle 64x48 1000", T0
    T0 = Machine.Ms: FOR I = 1 TO 100: Machine.FillTriangle 0, 0, 639, 0, 0, 479, C: NEXT I: REPORT "fill_triangle full 100", T0
    T0 = Machine.Ms: FOR I = 1 TO 1000: Machine.Triangle 0, 0, 639, 240, 100, 479, C: NEXT I: REPORT "triangle 1000", T0
    T0 = Machine.Ms: FOR I = 0 TO 999: X = (I * 7) MOD 576: Y = (I * 5) MOD 432: Machine.Blit 0, 0, 64, 48, X, Y: NEXT I: REPORT "blit 64x48 1000", T0
    T0 = Machine.Ms: FOR I = 0 TO 999: X = (I * 7) MOD 576: Y = (I * 5) MOD 432: Machine.Blit 0, 0, 64, 48, X, Y, -1, 0: NEXT I: REPORT "blit 64x48 key 1000", T0
    T0 = Machine.Ms: FOR I = 1 TO 1000: BK = Machine.GetBlock(0, 0, 64, 48): Machine.FreeBlock BK: NEXT I: REPORT "get_block 64x48 1000", T0
    BK = Machine.GetBlock(0, 0, 64, 48)
    T0 = Machine.Ms: FOR I = 0 TO 999: X = (I * 7) MOD 576: Y = (I * 5) MOD 432: Machine.PutBlock X, Y, 64, 48, BK: NEXT I: REPORT "put_block 64x48 1000", T0
    Machine.FreeBlock BK
    T0 = Machine.Ms: FOR I = 1 TO 100: Machine.FbClear 0: NEXT I: REPORT "clear 100", T0
NEXTMODE:
NEXT MI
Machine.Mode = 1
PRINT "BENCH done"
