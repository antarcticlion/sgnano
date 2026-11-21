10 REM Machine の 3 言語の突き合わせ（BASIC 版、2026-11-01）。docs/machine_api.md。api.rb・api.py と同じ行を出す
20 Machine.Mode = 3
30 K$ = "key1": S$ = Machine.KeyName(&H81): GOSUB 9100
40 K$ = "key2": S$ = Machine.KeyName(&H41): GOSUB 9100
50 K$ = "key3": S$ = Machine.KeyName(&HD): GOSUB 9100
60 K$ = "key4": S$ = Machine.KeyName(3): GOSUB 9100
70 K$ = "tattr": V = Machine.TAttr(14, 1, Machine.TEXT_BOLD): GOSUB 9000
80 K$ = "c1": V = Machine.TEXT_BOLD: GOSUB 9000
90 K$ = "c2": V = Machine.PAD_A: GOSUB 9000
100 K$ = "c3": V = Machine.PAD_UP: GOSUB 9000
110 K$ = "c4": V = Machine.KEY_F12: GOSUB 9000
120 K$ = "c5": V = Machine.TEXT_UNDERLINE: GOSUB 9000
130 K$ = "c6": V = Machine.TEXT_DOUBLE_WIDTH: GOSUB 9000
140 K$ = "c7": V = Machine.TEXT_GRAY: GOSUB 9000
150 K$ = "c8": V = Machine.TEXT_CLEAR: GOSUB 9000
160 K$ = "c9": V = Machine.TEXT_DEFAULT: GOSUB 9000
170 K$ = "rgb1": V = Machine.RGB(255, 0, 0): GOSUB 9000
180 K$ = "rgb2": V = Machine.RGB(0, 255, 0): GOSUB 9000
190 K$ = "pages": V = Machine.Pages: GOSUB 9000
200 Machine.WritePage = 1: Machine.VSync 1
210 K$ = "wp": V = Machine.WritePage: GOSUB 9000
220 Machine.WritePage = 0: Machine.VSync 1
230 K$ = "wp0": V = Machine.WritePage: GOSUB 9000
240 K$ = "bits": V = Machine.BitsPerPixel: GOSUB 9000
250 K$ = "bytes": V = Machine.BytesPerPixel: GOSUB 9000
260 K$ = "fbw": V = Machine.Width: GOSUB 9000
270 K$ = "fbh": V = Machine.Height: GOSUB 9000
280 Machine.FbClear 0: Machine.PSet 10, 10, 5
290 K$ = "pget": V = Machine.PGet(10, 10): GOSUB 9000
300 Machine.FillRect 20, 20, 10, 10, 7
310 K$ = "fill": V = Machine.PGet(25, 25): GOSUB 9000
320 Machine.Line 0, 50, 9, 50, 3
330 K$ = "line": V = Machine.PGet(5, 50): GOSUB 9000
340 Machine.Rect 40, 40, 10, 10, 4
350 K$ = "rect": V = Machine.PGet(40, 45): GOSUB 9000
360 Machine.FillTriangle 60, 60, 80, 60, 70, 80, 6
370 K$ = "tri": V = Machine.PGet(70, 65): GOSUB 9000
380 Machine.Triangle 90, 60, 110, 60, 100, 80, 2
390 K$ = "tri2": V = Machine.PGet(100, 60): GOSUB 9000
400 Machine.Blit 20, 20, 10, 10, 200, 200, 0
410 K$ = "blit": V = Machine.PGet(205, 205): GOSUB 9000
420 BK = Machine.GetBlock(20, 20, 4, 4): Machine.PutBlock 300, 300, 4, 4, BK: Machine.FreeBlock BK
430 K$ = "block": V = Machine.PGet(301, 301): GOSUB 9000
440 Machine.FbPalette 5, 255, 0, 0
450 K$ = "fbpal": V = ABS(Machine.FbPalette(5) = Machine.RGB(255, 0, 0)): GOSUB 9000
460 K$ = "lrready": V = ABS(Machine.LrReady): GOSUB 9000
470 K$ = "lrw": V = Machine.LrWidth: GOSUB 9000
480 K$ = "lrh": V = Machine.LrHeight: GOSUB 9000
490 K$ = "lrtiles": V = ABS(Machine.LrTiles > 0): GOSUB 9000
500 K$ = "lrpals": V = ABS(Machine.LrPalettes > 0): GOSUB 9000
510 Machine.LrPalette 0, 1, 255, 255, 255
520 P$ = "": FOR I = 0 TO 63: P$ = P$ + CHR$(I MOD 2): NEXT I
530 Machine.LrPattern 300, P$
540 Machine.LrMap 0, 1, 2, 300, 3, -1, 0
550 K$ = "map": S$ = MID$(STR$(Machine.LrMapGet(0, 1, 2, "tile")), 2) + "," + MID$(STR$(Machine.LrMapGet(0, 1, 2, "pal")), 2) + "," + MID$("falsetrue", 1 - 5 * Machine.LrMapGet(0, 1, 2, "hflip"), 5 + Machine.LrMapGet(0, 1, 2, "hflip")) + "," + MID$("falsetrue", 1 - 5 * Machine.LrMapGet(0, 1, 2, "vflip"), 5 + Machine.LrMapGet(0, 1, 2, "vflip")): GOSUB 9100
560 Machine.LrFillMap 1, 5, 2
570 K$ = "fill_map": S$ = MID$(STR$(Machine.LrMapGet(1, 0, 0, "tile")), 2) + "," + MID$(STR$(Machine.LrMapGet(1, 0, 0, "pal")), 2): GOSUB 9100
580 Machine.LrObj 5, 10, 20, 300, 8, 8, 1, 0
590 K$ = "obj": S$ = MID$(STR$(Machine.LrObjGet(5, "x")), 2) + "," + MID$(STR$(Machine.LrObjGet(5, "y")), 2) + "," + MID$(STR$(Machine.LrObjGet(5, "tile")), 2) + "," + MID$(STR$(ABS(Machine.LrObjGet(5, "shown"))), 2): GOSUB 9100
600 Machine.LrObjMove 5, 30, 40
610 K$ = "objmove": S$ = MID$(STR$(Machine.LrObjGet(5, "x")), 2) + "," + MID$(STR$(Machine.LrObjGet(5, "y")), 2): GOSUB 9100
620 Machine.LrObjHide 5
630 K$ = "objhide": V = ABS(Machine.LrObjGet(5, "shown")): GOSUB 9000
640 Machine.LrObjVisible -1
650 K$ = "objvis": V = ABS(Machine.LrObjVisible): GOSUB 9000
660 Machine.LrScroll 0, 3, 4: Machine.LrBgVisible 0, -1: Machine.LrRasterWave 0, STRING$(16, CHR$(128)), 0
670 Machine.LrBackdrop 10, 0, 0, 64: Machine.LrRaster 0, 20, 0, 1, 1: Machine.LrRasterClear
680 Machine.LrClear
690 K$ = "lrclear": V = Machine.LrMapGet(0, 1, 2, "tile"): GOSUB 9000
700 Machine.TextColor 14, 1
710 K$ = "tcolor": V = Machine.TextAttr AND 255: GOSUB 9000
720 Machine.TextPut 0, 26, "XYZ", Machine.TAttr(7)
730 K$ = "tget": S$ = CHR$(Machine.TextGet(1, 26)): GOSUB 9100
740 Machine.Locate 5, 6
750 K$ = "cursor": S$ = MID$(STR$(Machine.CursorX), 2) + "," + MID$(STR$(Machine.CursorY), 2): GOSUB 9100
760 K$ = "padx": V = Machine.PadDirX(0): GOSUB 9000
770 K$ = "pada": V = INT(Machine.PadAxis(0, 0)): GOSUB 9000
780 K$ = "pads": V = INT(Machine.PadStickX(0, "left")): GOSUB 9000
790 K$ = "padb": V = ABS(Machine.PadButton(0, 1)): GOSUB 9000
800 C = Machine.ClockSet
810 K$ = "clock": V = ABS(C = -1 OR C = 0): GOSUB 9000
820 K$ = "vinfo": V = ABS(LEN(Machine.VideoInfo("timing")) > 0): GOSUB 9000
830 K$ = "sinfo": V = ABS(Machine.SysInfo("uptime") > 0): GOSUB 9000
840 C = Machine.Mouse("connected")
850 K$ = "mouse": V = ABS(C = -1 OR C = 0): GOSUB 9000
860 Machine.Mode = 7
870 K$ = "bmready": V = ABS(Machine.BmReady): GOSUB 9000
880 K$ = "bmw": V = Machine.BmWidth: GOSUB 9000
890 K$ = "bmh": V = Machine.BmHeight: GOSUB 9000
900 Machine.BmPSet 1, 1, 9
910 K$ = "bmpget": V = Machine.BmPGet(1, 1): GOSUB 9000
920 Machine.BmWrite 640, "ABC"
930 K$ = "bmread": S$ = Machine.BmRead(640, 3): GOSUB 9100
940 Machine.BmPalette 9, 0, 255, 0
950 K$ = "bmpal": V = ABS(Machine.BmPalette(9) = Machine.RGB(0, 255, 0)): GOSUB 9000
955 REM PIO2 (ABI 5.0): pull block / mov isr, osr / push block の 3 語（ピンを使わない）
956 K$ = "pio2": V = ABS(Machine.Pio2Available): GOSUB 9000
957 R = Machine.Pio2SmClaim(0)
958 R = Machine.Pio2Insn(0, 32928)
959 R = Machine.Pio2Insn(1, 41159)
960 R = Machine.Pio2Insn(2, 32800)
961 OFF = Machine.Pio2Load(3)
962 K$ = "pio2load": V = ABS(OFF >= 0): GOSUB 9000
963 R = Machine.Pio2SmConfig(0, OFF, 1, 0, OFF + 2, OFF, 0)
964 R = Machine.Pio2SmEnable(0, 1)
965 R = Machine.Pio2SmPut(0, 305419896)
966 GOT = -1
967 FOR I = 1 TO 1000
968   G = Machine.Pio2SmGet(0)
969   IF G >= 0 AND GOT < 0 THEN GOT = G
970 NEXT I
971 K$ = "pio2fifo": V = ABS(GOT = 305419896): GOSUB 9000
972 R = Machine.Pio2SmEnable(0, 0)
973 R = Machine.Pio2SmUnclaim(0)
974 REM ADC (ABI 5.1/5.2): single reads, default L/R, A6/A7 on C, and temperature
975 K$ = "adcpins": V = Machine.AdcPins: GOSUB 9000
976 K$ = "adcpin0": V = Machine.AdcPin(0): GOSUB 9000
977 K$ = "adcread": V = ABS(Machine.AdcRead(40) >= 0): GOSUB 9000: TT = Machine.AdcTemperature: K$ = "adctemp": V = ABS(TT > -40 AND TT < 150): GOSUB 9000
978 K$ = "adcstart": V = ABS(Machine.AdcStart = 0): GOSUB 9000
979 Machine.VSync 6
980 K$ = "adcframes": V = ABS(Machine.AdcStats("frames") > 0): GOSUB 9000
981 Machine.AdcStop
982 C = Machine.AdcCanRead(46)
983 IF C THEN R = Machine.AdcStart(40, 41)
984 IF C THEN Machine.VSync 6
985 IF C THEN K$ = "adca6frames": V = ABS(Machine.AdcStats("frames") > 0): GOSUB 9000
986 IF C THEN Machine.AdcStop
987 REM Music (ABI 4.4, checked against Ruby/Python on 2026-11-18): constants and the idle state
988 K$ = "musicconst": V = Machine.MUSIC_MP3 + Machine.MUSIC_OGG * 10 + Machine.MUSIC_WAV * 100 + Machine.MUSIC_VGM * 1000 + Machine.MUSIC_LOOP * 10000: GOSUB 9000
989 K$ = "musicidle": V = Machine.MusicPlaying + Machine.MusicPaused * 2 + Machine.MusicPosition * 4 + Machine.MusicLength * 8 + Machine.MusicFormat * 16: GOSUB 9000
990 Machine.Mode = 1
991 PRINT "API-END"
992 END
9000 S$ = STR$(V): IF LEFT$(S$, 1) = " " THEN S$ = MID$(S$, 2)
9100 PRINT K$; "="; S$
9110 RETURN
