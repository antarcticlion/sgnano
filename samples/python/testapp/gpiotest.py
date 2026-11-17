# GPIO / PIO2 の自己テスト（MicroPython 版、2026-11-12）
# gpiotest.py [pin]  pin は C ボードなら GP34〜41 の空きピン。省くと SIO の回り込みは飛ばす。
import sys
import time
from machine import GPIO, PIO2

fails = 0
checks = 0

def check(name, ok):
    global fails, checks
    checks += 1
    if not ok:
        fails += 1
    print("  %-24s %s" % (name, "ok" if ok else "FAIL"))

print("GPIO / PIO2 test (MicroPython)")
if len(sys.argv) > 1:
    pin = int(sys.argv[1])
    print("gpio pin %d (SIO loopback)" % pin)
    check("gpio_init", GPIO.init(pin) == 0)
    check("gpio_set_dir(out)", GPIO.set_dir(pin, True) == 0)
    GPIO.put(pin, True)
    time.sleep(0.01)
    check("gpio high", GPIO.get(pin))
    GPIO.put(pin, False)
    time.sleep(0.01)
    check("gpio low", not GPIO.get(pin))
    check("gpio back to input", GPIO.init(pin) == 0)
else:
    print("gpio: skipped (give a free pin: gpiotest.py 34)")

check("pio2_available", PIO2.available())
prog = (0x80A0, 0xA0C7, 0x8020)       # pull block / mov isr, osr / push block
off = PIO2.load(prog)
check("pio2_load", off >= 0)
if off >= 0:
    check("pio2_sm_claim", PIO2.sm_claim(0) == 0)
    check("pio2_sm_config", PIO2.sm_config(0, off, 1, 0, off + 2, off, 0) == 0)
    check("pio2_sm_enable", PIO2.sm_enable(0, True) == 0)
    check("pio2_sm_put", PIO2.sm_put(0, 0x12345678))
    got = None
    for _ in range(1000):
        v = PIO2.sm_get(0)
        if isinstance(v, int) and v >= 0:
            got = v
            break
    check("pio2 TX -> RX", got == 0x12345678)
    print("  got 0x%08x (want 0x12345678)" % (got or 0))
    PIO2.sm_enable(0, False)
    check("pio2_sm_unclaim", PIO2.sm_unclaim(0) == 0)

print(("PASS" if fails == 0 else "FAIL") + ": %d checks, %d failed" % (checks, fails))
