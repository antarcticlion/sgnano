10 REM Primitive drawing demo (2026-11-13, SPEC_gfx.md). The same pictures as apps/gfxdemo (SGX),
20 REM samples/ruby/gfxdemo.rb and samples/python/gfxdemo.py. Mode 2 (RGB555), three pages. Any key: next, ESC: quit.
30 Machine.Mode = 2: Machine.TextVisible = 0
40 GOSUB 1000: GOSUB 9500: IF K = 27 THEN 90
50 GOSUB 2000: GOSUB 9500: IF K = 27 THEN 90
60 GOSUB 3000: GOSUB 9500
90 Machine.TextVisible = -1: Machine.Mode = 1: END
1000 REM ---- 1. shapes and lines ----
1010 T$ = "1. shapes and lines": GOSUB 9000
1020 Machine.Bk Machine.BK_OPAQUE, Machine.FbRgb(4, 4, 10)
1030 FOR I = 0 TO 5
1040 Machine.Pen Machine.FbRgb(31, 31, 31): Machine.Brush Machine.FbRgb(31, 20, 5 * I), Machine.BS_HORIZONTAL + I
1050 Machine.Rectangle 20 + I * 100, 60, 100 + I * 100, 120
1060 NEXT I
1070 Machine.Bk Machine.BK_TRANSPARENT
1080 Machine.Pen Machine.FbRgb(31, 31, 0), 3: Machine.Brush Machine.FbRgb(0, 12, 31): Machine.RoundRect 20, 140, 150, 230, 40, 40
1090 Machine.Brush Machine.FbRgb(31, 8, 8): Machine.Ellipse 170, 140, 300, 230
1100 Machine.Brush Machine.FbRgb(8, 28, 8): Machine.Pie 320, 130, 440, 240, 440, 185, 380, 130
1110 Machine.Brush Machine.FbRgb(28, 8, 28): Machine.Chord 460, 140, 620, 230, 620, 185, 460, 185
1120 Machine.Pen Machine.FbRgb(31, 31, 31): Machine.Brush Machine.FbRgb(31, 24, 0)
1130 Machine.FillRule Machine.FILL_NONZERO: Machine.Polygon 80, 250, 104, 330, 30, 280, 130, 280, 56, 330
1140 Machine.FillRule Machine.FILL_EVENODD: Machine.Polygon 230, 250, 254, 330, 180, 280, 280, 280, 206, 330
1150 Machine.FillRule Machine.FILL_NONZERO
1160 FOR I = 0 TO 4: Machine.Pen Machine.FbRgb(20, 31, 31), 1, I: Machine.MoveTo 320, 260 + I * 14: Machine.LineTo 620, 260 + I * 14: NEXT I
1170 FOR I = 0 TO 2
1180 X = 330 + I * 100
1190 Machine.Pen Machine.FbRgb(31, 16, 0), 14: Machine.PenExt I, I
1200 Machine.Polyline X, 440, X + 40, 360, X + 80, 440
1210 Machine.Pen Machine.FbRgb(31, 31, 31): Machine.Polyline X, 440, X + 40, 360, X + 80, 440
1220 NEXT I
1230 FOR I = 0 TO 5
1240 Machine.Pen Machine.FbRgb(31 - I * 5, I * 6, 31), 2: Machine.PolyBezier 20, 440, 80, 350 + I * 12, 200, 470 - I * 12, 290, 380
1250 NEXT I
1260 RETURN
2000 REM ---- 2. paths and text ----
2010 T$ = "2. paths and text": GOSUB 9000
2020 Machine.Brush Machine.FbRgb(31, 22, 6): Machine.Pen Machine.FbRgb(31, 31, 31), 2: Machine.Aa 1
2030 Machine.BeginPath: Machine.PathMoveTo 90, 60
2040 Machine.PathQuadTo 160, 60, 160, 130: Machine.PathQuadTo 160, 200, 90, 200: Machine.PathQuadTo 20, 200, 20, 130: Machine.PathQuadTo 20, 60, 90, 60: Machine.ClosePath
2050 Machine.PathMoveTo 90, 95
2060 Machine.PathQuadTo 60, 95, 60, 130: Machine.PathQuadTo 60, 165, 90, 165: Machine.PathQuadTo 120, 165, 120, 130: Machine.PathQuadTo 120, 95, 90, 95: Machine.ClosePath
2070 Machine.FillStrokePath
2080 FOR SIDE = 0 TO 1
2090 Machine.Aa SIDE
2100 FOR I = 0 TO 3
2110 Machine.Brush Machine.FbRgb(8 + 6 * I, 16, 31 - 6 * I): Machine.Pen 0, 1, Machine.PS_NULL
2120 CX = 230 + SIDE * 200 + I * 40: R = 50 - 9 * I: RT = I * 0.3
2130 Machine.BeginPath
2140 FOR J = 0 TO 9
2150 A = RT + J * 3.14159265 / 5: RR = R: IF J MOD 2 = 1 THEN RR = R * 0.45
2160 PX = CX + RR * SIN(A): PY = 130 - RR * COS(A)
2170 IF J = 0 THEN Machine.PathMoveTo PX, PY ELSE Machine.PathLineTo PX, PY
2180 NEXT J
2190 Machine.ClosePath: Machine.FillPath
2200 NEXT I
2210 NEXT SIDE
2220 Machine.Aa 0: Machine.Bk Machine.BK_TRANSPARENT
2230 X = 20
2240 RESTORE 2900
2250 FOR I = 1 TO 5
2260 READ W, F, S$
2270 Machine.Font Machine.FONT_ROM, 24, W, F: Machine.FbTextColor Machine.FbRgb(31, 31, 20)
2280 Machine.TextOut X, 230, S$: X = X + Machine.TextExtentW(S$) + 20
2290 NEXT I
2300 Machine.Font Machine.FONT_ROM, 16, 400, 0, 900: Machine.FbTextColor Machine.FbRgb(20, 31, 20): Machine.TextOut 600, 440, "rotated 90"
2310 Machine.Font Machine.FONT_ROM, 48, Machine.FW_BOLD: Machine.FbTextColor Machine.FbRgb(31, 16, 31): Machine.TextOut 20, 270, "描画 Draw"
2320 P$ = "DrawText wraps this paragraph inside the rectangle and centres every line. 日本語も字の境で折り返す。"
2330 Machine.Pen Machine.FbRgb(12, 12, 20), 1, Machine.PS_DOT: Machine.Brush 0, Machine.BS_NULL: Machine.Rectangle 296, 266, 584, 444
2340 Machine.Font Machine.FONT_ROM, 16: Machine.FbTextColor Machine.FbRgb(31, 31, 31)
2350 H = Machine.DrawText(P$, 300, 270, 580, 440, Machine.DT_WORDBREAK + Machine.DT_CENTER)
2360 RETURN
2900 DATA 400, 0, "Normal", 700, 0, "Bold", 400, 1, "Italic", 400, 2, "Underline", 400, 4, "Strike"
3000 REM ---- 3. bitmaps ----
3010 T$ = "3. bitmaps": GOSUB 9000
3020 IM = Machine.ImgNew(64, 64): KY = Machine.ImgRgb(IM, 31, 0, 31)
3030 Machine.ImgClear IM, KY
3040 Machine.ImgPen IM, Machine.ImgRgb(IM, 31, 31, 31), 2: Machine.ImgBrush IM, Machine.ImgRgb(IM, 0, 20, 31): Machine.ImgEllipse IM, 4, 4, 60, 60
3050 Machine.ImgBrush IM, Machine.ImgRgb(IM, 31, 31, 0)
3060 Machine.PtClear: Machine.PtAdd 16, 28, 36, 28, 36, 18, 50, 32: Machine.PtAdd 36, 46, 36, 36, 16, 36: Machine.ImgPolygon IM
3070 FOR Y = 60 TO 420 STEP 20: FOR X = 0 TO 620 STEP 20
3080 C = Machine.FbRgb(3, 3, 6): IF ((X + Y) \ 20) MOD 2 = 1 THEN C = Machine.FbRgb(6, 6, 10)
3090 Machine.FillRect X, Y, 20, 20, C
3100 NEXT X: NEXT Y
3110 Machine.Bitblt 20, 80, 64, 64, IM
3120 Machine.Bitblt 100, 80, 64, 64, IM, 0, 0, Machine.SRCCOPY, KY
3130 Machine.StretchBlt 180, 80, 128, 128, IM, 0, 0, 64, 64, Machine.SRCCOPY, KY
3140 Machine.StretchBlt 452, 80, -128, 128, IM, 0, 0, 64, 64, Machine.SRCCOPY, KY
3150 Machine.StretchBlt 470, 208, 160, -128, IM, 0, 0, 64, 64, Machine.SRCCOPY, KY
3160 Machine.Bitblt 20, 240, 64, 64, IM, 0, 0, Machine.SRCINVERT
3170 Machine.Bitblt 100, 240, 64, 64, IM, 0, 0, Machine.NOTSRCCOPY
3180 FOR I = 0 TO 7: S = 16 + I * 6: Machine.StretchBlt 20 + I * 70, 330, S, S, IM, 0, 0, 64, 64, Machine.SRCCOPY, KY: NEXT I
3190 D$ = "": FOR I = 0 TO 31: D$ = D$ + CHR$(I * 8) + CHR$(255 - I * 8) + CHR$(128 + I * 4): NEXT I
3200 Machine.DrawDib 200, 240, 400, 60, D$, Machine.DIB_RGB888, 32, 1
3210 Machine.ImgFree IM
3220 RETURN
9000 REM ---- clear and title ----
9010 Machine.ResetDrawing: Machine.FbClear Machine.FbRgb(2, 3, 6)
9020 Machine.Font Machine.FONT_ROM, 32, Machine.FW_BOLD: Machine.FbTextColor Machine.FbRgb(31, 31, 31): Machine.Bk Machine.BK_TRANSPARENT
9030 Machine.TextOut 16, 8, T$
9040 Machine.Font Machine.FONT_ROM, 16: Machine.FbTextColor Machine.FbRgb(20, 20, 20), Machine.TA_RIGHT
9050 Machine.TextOut 624, 456, "any key: next   ESC: quit"
9060 RETURN
9500 K = Machine.WaitKey: RETURN
