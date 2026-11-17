# GPIO / PIO2 の自己テスト（mruby 版、2026-11-12）
# gpiotest.rb [pin]  pin は C ボードなら GP34〜41 の空きピン。省くと SIO の回り込みは飛ばす。
# PIO2 は pull / mov isr, osr / push の 3 語で TX→RX を確かめる（gpiotest.c と同じ）。
M = Machine
GPIO = M::GPIO
PIO2 = M::PIO2
$fails = 0
$checks = 0

def check(name, ok)
  $checks += 1
  $fails += 1 unless ok
  printf("  %-24s %s\n", name, ok ? "ok" : "FAIL")
end

puts "GPIO / PIO2 test (mruby)"
if ARGV.length > 0
  pin = ARGV[0].to_i
  puts "gpio pin #{pin} (SIO loopback)"
  check("gpio_init", GPIO.init(pin) == 0)
  check("gpio_set_dir(out)", GPIO.set_dir(pin, true) == 0)
  GPIO.put(pin, true)
  sleep_ms(10)
  check("gpio high", GPIO.get(pin))
  GPIO.put(pin, false)
  sleep_ms(10)
  check("gpio low", !GPIO.get(pin))
  check("gpio back to input", GPIO.init(pin) == 0)
else
  puts "gpio: skipped (give a free pin: gpiotest.rb 34)"
end

check("pio2_available", PIO2.available?)
prog = [0x80A0, 0xA0C7, 0x8020]       # pull block / mov isr, osr / push block
off = PIO2.load(prog)
check("pio2_load", off >= 0)
if off >= 0
  check("pio2_sm_claim", PIO2.sm_claim(0) == 0)
  check("pio2_sm_config", PIO2.sm_config(0, off, 1, 0, off + 2, off, 0) == 0)
  check("pio2_sm_enable", PIO2.sm_enable(0, true) == 0)
  check("pio2_sm_put", PIO2.sm_put(0, 0x12345678))
  got = nil
  1000.times do
    v = PIO2.sm_get(0)
    if v.is_a?(Integer) && v >= 0
      got = v
      break
    end
  end
  check("pio2 TX -> RX", got == 0x12345678)
  printf("  got 0x%08x (want 0x12345678)\n", got || 0)
  PIO2.sm_enable(0, false)
  check("pio2_sm_unclaim", PIO2.sm_unclaim(0) == 0)
end

puts(($fails == 0 ? "PASS" : "FAIL") + ": #{$checks} checks, #{$fails} failed")
