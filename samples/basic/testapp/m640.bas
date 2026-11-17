' Mandelbrot set, 640 x 480, on the framebuffer (mode 2). SG BASIC 版（2026-11-12）
' m640.py / m640.rb の移植。実軸について対称なので上半分を計算して下へ写す。
' 主のカージオイドと周期 2 の円の内側は、発散しないので計算を飛ばす。
' SG BASIC の IF は 1 行だけ。EXIT は FUNCTION/SUB の中だけなので、ループは条件で抜ける。
DEFDBL A-Z
Machine.Mode = 2
Machine.FbClear 0

MX = 64
DIM PAL(MX)
FOR I = 0 TO MX - 1
    T = I / MX
    U = 1 - T
    PAL(I) = Machine.RGB(INT(9 * U * T * T * T * 255), INT(15 * U * U * T * T * 255), INT(8.5 * U * U * U * T * 255))
NEXT I
PAL(MX) = 0

W = 640
H = 480
X0 = -2.2
DX = 3.2 / W
Y0 = -1.2
DY = 2.4 / H
FOR PY = 0 TO H / 2 - 1
    CI = Y0 + (PY + 0.5) * DY
    CI2 = CI * CI
    FOR PX = 0 TO W - 1
        CR = X0 + PX * DX
        Q = (CR - 0.25) * (CR - 0.25) + CI2
        SKIP = 0
        IF Q * (Q + (CR - 0.25)) <= 0.25 * CI2 THEN SKIP = -1
        IF (CR + 1) * (CR + 1) + CI2 <= 0.0625 THEN SKIP = -1
        IF SKIP THEN N = MX ELSE ZR = 0: ZI = 0: N = 0
        ZR2 = 0
        ZI2 = 0
        WHILE N < MX AND ZR2 + ZI2 <= 4
            ZI = 2 * ZR * ZI + CI
            ZR = ZR2 - ZI2 + CR
            N = N + 1
            ZR2 = ZR * ZR
            ZI2 = ZI * ZI
        WEND
        C = PAL(N)
        Machine.PSet PX, PY, C
        Machine.PSet PX, H - 1 - PY, C
    NEXT PX
NEXT PY
PRINT "done"
