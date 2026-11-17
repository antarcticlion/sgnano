10 REM Primitive drawing (2026-11-13, SPEC_gfx.md): the Machine drawing members checked with PGet.
20 REM The same checks as samples/ruby/gfx.rb and samples/python/gfx.py (points through PtClear / PtAdd).
30 NG = 0
40 Machine.Mode = 2: Machine.FbClear 0
50 WH = Machine.FbRgb(31, 31, 31): RD = Machine.FbRgb(31, 0, 0): BL = Machine.FbRgb(0, 0, 31): GR = Machine.FbRgb(0, 31, 0)
100 REM --- closed shapes ---
110 Machine.Pen WH: Machine.Brush RD: Machine.Rectangle 10, 10, 50, 40
120 N$ = "rectangle outline": C = (Machine.PGet(10, 10) = WH) AND (Machine.PGet(49, 39) = WH) AND (Machine.PGet(50, 40) = 0): GOSUB 9000
130 N$ = "rectangle inside": C = (Machine.PGet(30, 25) = RD): GOSUB 9000
140 Machine.Pen WH, 1, Machine.PS_NULL: Machine.Brush BL: Machine.Ellipse 100, 10, 200, 90
150 N$ = "ellipse without a pen": C = (Machine.PGet(150, 50) = BL) AND (Machine.PGet(101, 11) = 0): GOSUB 9000
160 Machine.Pen GR: Machine.Brush 0, Machine.BS_NULL: Machine.RoundRect 220, 10, 300, 70, 30, 30
170 N$ = "round rect": C = (Machine.PGet(260, 10) = GR) AND (Machine.PGet(260, 40) = 0) AND (Machine.PGet(220, 10) = 0): GOSUB 9000
180 Machine.Pen WH, 1, Machine.PS_NULL: Machine.Brush RD: Machine.Polygon 320, 10, 400, 10, 360, 70
190 N$ = "polygon": C = (Machine.PGet(360, 30) = RD) AND (Machine.PGet(330, 60) = 0): GOSUB 9000
200 Machine.Pie 420, 10, 520, 110, 520, 60, 470, 10
210 N$ = "pie": C = (Machine.PGet(495, 35) = RD) AND (Machine.PGet(445, 85) = 0): GOSUB 9000
300 REM --- lines and curves ---
310 Machine.Pen WH: Machine.MoveTo 10, 120: Machine.LineTo 100, 120
320 N$ = "move_to / line_to": C = (Machine.PGet(10, 120) = WH) AND (Machine.PGet(100, 120) = WH): GOSUB 9000
330 Machine.PtClear: Machine.PtAdd 10, 130, 60, 130, 60, 160: Machine.Polyline
340 N$ = "polyline (point buffer)": C = (Machine.PGet(60, 145) = WH): GOSUB 9000
350 Machine.PolyBezier 10, 230, 40, 170, 90, 170, 120, 230
360 N$ = "poly_bezier ends": C = (Machine.PGet(10, 230) = WH) AND (Machine.PGet(120, 230) = WH): GOSUB 9000
370 Machine.Pen GR, 9: Machine.PenExt Machine.CAP_FLAT, Machine.JOIN_MITER: Machine.MoveTo 150, 140: Machine.LineTo 300, 140
380 N$ = "wide pen (9)": C = (Machine.PGet(200, 136) = GR) AND (Machine.PGet(200, 144) = GR) AND (Machine.PGet(200, 146) = 0): GOSUB 9000
390 Machine.Pen WH, 1, Machine.PS_DASH: Machine.MoveTo 150, 170: Machine.LineTo 400, 170
400 N$ = "dashed pen": C = (Machine.PGet(150, 170) = WH) AND (Machine.PGet(170, 170) <> WH): GOSUB 9000
500 REM --- path with a matrix ---
510 Machine.Pen WH, 1, Machine.PS_NULL: Machine.Brush BL: Machine.Matrix 40, 0, 0, 40, 450, 150
520 Machine.BeginPath: Machine.PathMoveTo 0, 0: Machine.PathLineTo 1, 0: Machine.PathLineTo 1, 1: Machine.PathLineTo 0, 1
530 Machine.ClosePath: Machine.FillPath: Machine.ResetMatrix
540 N$ = "path through the matrix": C = (Machine.PGet(450, 150) = BL) AND (Machine.PGet(489, 189) = BL) AND (Machine.PGet(490, 190) <> BL): GOSUB 9000
600 REM --- text ---
610 Machine.Font Machine.FONT_ROM, 32: Machine.FbTextColor WH: Machine.Bk Machine.BK_TRANSPARENT
620 Machine.TextOut 150, 260, "Ag"
630 N$ = "text_extent": C = (Machine.TextExtentW("Ag") > 0) AND (Machine.TextExtentH("Ag") = 32): GOSUB 9000
640 Machine.Font Machine.FONT_8X8, 8
650 N$ = "draw_text lines": C = (Machine.DrawText("left" + CHR$(10) + "centre" + CHR$(10) + "right", 400, 260, 480, 300, Machine.DT_CENTER) = 24): GOSUB 9000
700 REM --- images ---
710 IM = Machine.ImgNew(16, 16)
720 N$ = "image size": C = (Machine.ImgWidth(IM) = 16) AND (Machine.ImgHeight(IM) = 16): GOSUB 9000
730 Machine.ImgClear IM, BL: Machine.ImgPen IM, RD: Machine.ImgBrush IM, RD: Machine.ImgRectangle IM, 4, 4, 12, 12
740 Machine.Bitblt 10, 350, 16, 16, IM
750 N$ = "bitblt from an image": C = (Machine.PGet(10, 350) = BL) AND (Machine.PGet(18, 358) = RD): GOSUB 9000
760 Machine.StretchBlt 40, 350, 32, 32, IM, 0, 0, 16, 16
770 N$ = "stretch_blt x2": C = (Machine.PGet(40, 350) = BL) AND (Machine.PGet(56, 366) = RD) AND (Machine.PGet(71, 381) = BL): GOSUB 9000
780 Machine.Bitblt 80, 350, 16, 16, IM, 0, 0, Machine.SRCCOPY, BL
790 N$ = "transparent key": C = (Machine.PGet(80, 350) = 0) AND (Machine.PGet(88, 358) = RD): GOSUB 9000
800 Machine.ImgFree IM
900 REM --- CLUT8 (mode 3) and the bitmap (mode 7) ---
905 REM a mode that cannot be opened (SRAM) is skipped: ON ERROR jumps to 9100 and goes on at the next step
907 ON ERROR GOTO 9100: SK = 0: STP = 920
910 Machine.Mode = 3
915 IF SK = 0 THEN Machine.FbClear 0: Machine.Pen 15: Machine.Brush 4: Machine.Rectangle 10, 10, 30, 30: N$ = "CLUT8 rectangle": C = (Machine.PGet(10, 10) = 15) AND (Machine.PGet(20, 20) = 4): GOSUB 9000
920 SK = 0: STP = 950
930 Machine.Mode = 7
940 IF SK = 0 THEN Machine.BmClear 0: Machine.BmPen 15: Machine.BmBrush 9: Machine.BmEllipse 100, 50, 220, 150: N$ = "bitmap ellipse": C = (Machine.BmPGet(160, 100) = 9) AND (Machine.BmPGet(100, 100) = 15): GOSUB 9000
950 ON ERROR GOTO 0: Machine.Mode = 1
960 IF NG = 0 THEN PRINT "gfx: all ok" ELSE PRINT "gfx:"; NG; "NG"
970 END
9000 IF C THEN PRINT "ok "; N$ ELSE PRINT "NG "; N$: NG = NG + 1
9010 RETURN
9100 PRINT "skip the mode (SRAM)": SK = 1: RESUME NEXT
