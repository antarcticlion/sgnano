' Mandelbrot set in text (79 x 24). SG BASIC 版（2026-11-12）
' mandel.py / mandel.rb の移植。文字だけなので画面モード 1。
' EXIT は FUNCTION/SUB の中だけなので、WHILE の条件で抜ける。
DEFDBL A-Z
Machine.Mode = 1
CH$ = " .,:-=+*%#"
ITER = 40
H = 24
W = 79
FOR Y = 0 TO H - 1
    CI = (Y - H / 2) * 2.4 / H
    LINE$ = ""
    FOR X = 0 TO W - 1
        CR = (X - W * 0.65) * 3.2 / W
        ZR = 0
        ZI = 0
        N = 0
        WHILE N < ITER AND ZR * ZR + ZI * ZI < 4
            T = ZR * ZR - ZI * ZI + CR
            ZI = 2 * ZR * ZI + CI
            ZR = T
            N = N + 1
        WEND
        IF N = ITER THEN LINE$ = LINE$ + "@" ELSE LINE$ = LINE$ + MID$(CH$, (N MOD 10) + 1, 1)
    NEXT X
    PRINT LINE$
NEXT Y
