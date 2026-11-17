' FONT DEMO (2026-11-02): every text decoration in one screen -- colours, bold,
' underline, strike, overline, reverse, blink, left/right border lines, rotation,
' double width/height, and the outer frame of doubled characters.
' The same layout is in samples/ruby/fontdemo.rb and samples/python/fontdemo.py.
' Any key ends it. The status row shows a running frame number.
DEFDBL A-Z
Machine.Mode = 1
Machine.ClearKeys
Machine.TextClear Machine.TEXT_CLEAR

FUNCTION DS(BYVAL V) AS STRING          ' an integer as text, no leading space
    DSX$ = STR$(INT(V))
    IF LEFT$(DSX$, 1) = " " THEN DSX$ = MID$(DSX$, 2)
    DS = DSX$
END FUNCTION

SUB LAB(BYVAL X, BYVAL Y, BYVAL S$)
    Machine.TextPut X, Y, S$, Machine.TAttr(7, 0)
END SUB

SUB TILE(BYVAL X, BYVAL Y, BYVAL S$, BYVAL FG, BYVAL BG, BYVAL F)
    Machine.TextPut X, Y, S$, Machine.TAttr(FG, BG, F)
END SUB

' A word with a box around the whole word: top/bottom on every cell, left on the
' first cell and right on the last cell.
SUB FRAMED(BYVAL X, BYVAL Y, BYVAL S$, BYVAL FG, BYVAL BG)
    N = LEN(S$)
    FOR I = 1 TO N
        F = Machine.TEXT_OVERLINE + Machine.TEXT_UNDERLINE
        IF I = 1 THEN F = F + Machine.TEXT_LEFT_LINE
        IF I = N THEN F = F + Machine.TEXT_RIGHT_LINE
        Machine.TextPut X + I - 1, Y, MID$(S$, I, 1), Machine.TAttr(FG, BG, F)
    NEXT I
END SUB

Machine.TextPut 0, 0, "FONT DEMO  --  colours, styles, lines, rotation, double size", Machine.TAttr(15, 0, Machine.TEXT_BOLD)

' row 1: one flag each
LAB 0, 1, "normal":  TILE 7, 1, "A", 15, 0, 0
LAB 10, 1, "bold":   TILE 15, 1, "B", 14, 0, Machine.TEXT_BOLD
LAB 18, 1, "under":  TILE 24, 1, "C", 13, 0, Machine.TEXT_UNDERLINE
LAB 27, 1, "strike": TILE 34, 1, "D", 11, 0, Machine.TEXT_STRIKE
LAB 37, 1, "over":   TILE 42, 1, "E", 12, 0, Machine.TEXT_OVERLINE
LAB 45, 1, "reverse":TILE 53, 1, "F", 10, 0, Machine.TEXT_REVERSE
LAB 56, 1, "blink":  TILE 62, 1, "G", 13, 0, Machine.TEXT_BLINK

' row 2: left / right lines, a frame, and combinations
LAB 0, 2, "left":  TILE 5, 2, "H", 15, 0, Machine.TEXT_LEFT_LINE
LAB 8, 2, "right": TILE 14, 2, "I", 14, 0, Machine.TEXT_RIGHT_LINE
LAB 17, 2, "both": TILE 22, 2, "J", 12, 0, Machine.TEXT_LEFT_LINE + Machine.TEXT_RIGHT_LINE
LAB 25, 2, "frame": FRAMED 31, 2, "FRAME", 15, 1
LAB 40, 2, "bold+under+over": TILE 55, 2, "K", 11, 0, Machine.TEXT_BOLD + Machine.TEXT_UNDERLINE + Machine.TEXT_OVERLINE
LAB 58, 2, "blink+bold":      TILE 69, 2, "L", 10, 0, Machine.TEXT_BLINK + Machine.TEXT_BOLD

' rows 3 / 4: the 16 colours as background and as foreground
LAB 0, 3, "bg colours:"
FOR I = 0 TO 15
    FG = 0: IF I = 0 OR I = 8 THEN FG = 15
    Machine.TextPut 12 + I * 4, 3, " " + HEX$(I) + "  ", Machine.TAttr(FG, I)
NEXT I
LAB 0, 4, "fg colours:"
FOR I = 0 TO 15
    BG = 0: IF I = 0 THEN BG = 7
    Machine.TextPut 12 + I * 4, 4, " " + HEX$(I) + "  ", Machine.TAttr(I, BG)
NEXT I

' rows 5-6: double width / height / both
LAB 0, 5, "double:"
TILE 9, 5, "WIDE", 14, 0, Machine.TEXT_DOUBLE_WIDTH
TILE 18, 5, "TALL", 13, 0, Machine.TEXT_DOUBLE_HEIGHT
TILE 23, 5, "BOTH", 11, 0, Machine.TEXT_DOUBLE_WIDTH + Machine.TEXT_DOUBLE_HEIGHT
TILE 32, 5, "漢", 12, 0, Machine.TEXT_DOUBLE_WIDTH + Machine.TEXT_DOUBLE_HEIGHT
TILE 37, 5, "字", 12, 0, Machine.TEXT_DOUBLE_WIDTH + Machine.TEXT_DOUBLE_HEIGHT
LAB 0, 7, "double width / double height / both"

' rows 8-9: the outer frame of a doubled character (all four lines)
LAB 0, 8, "lines on double:"
TILE 17, 8, "漢", 15, 1, Machine.TEXT_DOUBLE_WIDTH + Machine.TEXT_DOUBLE_HEIGHT + Machine.TEXT_LEFT_LINE + Machine.TEXT_RIGHT_LINE + Machine.TEXT_OVERLINE + Machine.TEXT_UNDERLINE
LAB 22, 8, "outer frame"

' row 10: rotation and combinations
LAB 0, 10, "rotate:"
TILE 8, 10, "A", 15, 0, Machine.TEXT_ROT90
TILE 10, 10, "B", 15, 0, Machine.TEXT_ROT180
TILE 12, 10, "C", 15, 0, Machine.TEXT_ROT270
LAB 15, 10, "bold+under+over": TILE 30, 10, "D", 12, 0, Machine.TEXT_BOLD + Machine.TEXT_UNDERLINE + Machine.TEXT_OVERLINE
LAB 33, 10, "reverse":         TILE 41, 10, "漢字", 15, 0, Machine.TEXT_REVERSE
LAB 46, 10, "blink":           TILE 52, 10, "E", 10, 0, Machine.TEXT_BLINK + Machine.TEXT_BOLD

' row 11: full-width kanji, each rotation
LAB 0, 11, "kanji:"
TILE 7, 11, "漢字", 14, 0, 0
TILE 13, 11, "漢字", 14, 0, Machine.TEXT_ROT90
TILE 19, 11, "漢字", 14, 0, Machine.TEXT_ROT180
TILE 25, 11, "漢字", 14, 0, Machine.TEXT_ROT270
LAB 31, 11, "left+right:": TILE 43, 11, "漢", 13, 0, Machine.TEXT_LEFT_LINE + Machine.TEXT_RIGHT_LINE

' row 12: boxes and other combinations
LAB 0, 12, "box:": FRAMED 5, 12, "ABCDE", 15, 1
LAB 13, 12, "left+right 漢:": TILE 29, 12, "漢", 12, 0, Machine.TEXT_LEFT_LINE + Machine.TEXT_RIGHT_LINE + Machine.TEXT_OVERLINE + Machine.TEXT_UNDERLINE
LAB 34, 12, "blink+reverse:": TILE 48, 12, "F", 10, 0, Machine.TEXT_BLINK + Machine.TEXT_REVERSE

' status row
BAR = Machine.TAttr(0, Machine.TEXT_CYAN)
Machine.TextPut 0, 27, SPACE$(80), BAR
Machine.TextPut 1, 27, "FONT DEMO -- press any key to end", BAR
N = 0: K = 0
WHILE K = 0
    K = Machine.Key
    IF K = -1 THEN K = 0
    Machine.TextPut 64, 27, "frame " + RIGHT$("      " + DS(N), 6), BAR
    Machine.VSync
    N = N + 1
WEND
Machine.TextClear
PRINT "fontdemo: bye"
