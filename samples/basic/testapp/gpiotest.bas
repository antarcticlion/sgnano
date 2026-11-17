' GPIO / PIO2 の自己テスト（SG BASIC 版、2026-11-12）
' gpiotest.bas [pin]  pin は C ボードなら GP34〜41 の空きピン。省くと SIO の回り込みは飛ばす。
' PIO2 は pull / mov isr, osr / push の 3 語で TX→RX を確かめる（gpiotest.c と同じ）。
' SG BASIC の IF は 1 行だけなので、まとまった処理は SUB にしている。
PIN = VAL(COMMAND$)
IF PIN = 0 THEN PIN = 34
FAILS = 0
CHECKS = 0

SUB CHECK(BYVAL NAME$, BYVAL OK)
    CHECKS = CHECKS + 1
    IF NOT OK THEN FAILS = FAILS + 1
    IF OK THEN PRINT "  "; NAME$; " ok" ELSE PRINT "  "; NAME$; " FAIL"
END SUB

SUB GPIOTEST
    PRINT "gpio pin "; PIN; " (SIO loopback)"
    CHECK "gpio_init", Machine.GpioInit(PIN) = 0
    CHECK "gpio_set_dir(out)", Machine.GpioSetDir(PIN, 1) = 0
    Machine.GpioPut PIN, 1
    Machine.VSync 1
    CHECK "gpio high", Machine.GpioGet(PIN)
    Machine.GpioPut PIN, 0
    Machine.VSync 1
    CHECK "gpio low", NOT Machine.GpioGet(PIN)
    CHECK "gpio back to input", Machine.GpioInit(PIN) = 0
END SUB

SUB PIOTEST
    CHECK "pio2_sm_claim", Machine.Pio2SmClaim(0) = 0
    CHECK "pio2_sm_config", Machine.Pio2SmConfig(0, OFF, 1, 0, OFF + 2, OFF, 0) = 0
    CHECK "pio2_sm_enable", Machine.Pio2SmEnable(0, 1) = 0
    CHECK "pio2_sm_put", Machine.Pio2SmPut(0, 305419896)
    GOT = -1
    FOR I = 1 TO 1000
        G = Machine.Pio2SmGet(0)
        IF G >= 0 AND GOT < 0 THEN GOT = G
    NEXT I
    CHECK "pio2 TX -> RX", GOT = 305419896
    IF GOT >= 0 THEN HI = INT(GOT / 65536): LO = GOT - HI * 65536: PRINT "  got 0x"; RIGHT$("0000" + HEX$(HI), 4); RIGHT$("0000" + HEX$(LO), 4); " (want 0x12345678)" ELSE PRINT "  got none (want 0x12345678)"
    R = Machine.Pio2SmEnable(0, 0)
    CHECK "pio2_sm_unclaim", Machine.Pio2SmUnclaim(0) = 0
END SUB

PRINT "GPIO / PIO2 test (SG BASIC)"
IF PIN > 0 THEN GPIOTEST ELSE PRINT "gpio: skipped (give a free pin: gpiotest.bas 34)"
CHECK "pio2_available", Machine.Pio2Available
R = Machine.Pio2Insn(0, 32928)
R = Machine.Pio2Insn(1, 41159)
R = Machine.Pio2Insn(2, 32800)
OFF = Machine.Pio2Load(3)
CHECK "pio2_load", OFF >= 0
IF OFF >= 0 THEN PIOTEST
IF FAILS = 0 THEN PRINT "PASS: "; CHECKS; " checks, 0 failed" ELSE PRINT "FAIL: "; CHECKS; " checks, "; FAILS; " failed"
