# Pad helpers on the device (2026-10-18): press the buttons, move the sticks. q ends it (ESC also stops).
# The screen shows what is held now; the log (and the bottom rows) get a line on every press and release.
M = Machine
NAMES = { M::PAD_X => "X", M::PAD_A => "A", M::PAD_B => "B", M::PAD_Y => "Y", M::PAD_LB => "LB", M::PAD_RB => "RB",
          M::PAD_LT => "LT", M::PAD_RT => "RT", M::PAD_BACK => "BACK", M::PAD_START => "START", M::PAD_LS => "LS", M::PAD_RS => "RS",
          M::PAD_UP => "UP", M::PAD_DOWN => "DOWN", M::PAD_LEFT => "LEFT", M::PAD_RIGHT => "RIGHT" }
M.text_clear
M.text_put(0, 0, "pad test: press the buttons and move the sticks. q to quit", M.tattr(15, 1))
log = []
loop do
  break if M.key == "q".ord
  M.vsync
  4.times do |i|
    d = M.pad(i)
    unless d
      M.text_put(0, 2 + i * 3, format("pad %d: --", i).ljust(79), M.tattr(8))
      next
    end
    held = NAMES.select { |n, _| M.pad_button?(i, n) }.values.join(" ")
    lx, ly = M.pad_stick(i, :left); rx, ry = M.pad_stick(i, :right)
    M.text_put(0, 2 + i * 3, format("pad %d: %04X:%04X  dir %-8s held %s", i, d[:vid], d[:pid], M.pad_dir(i).inspect, held).ljust(79), M.tattr(15))
    M.text_put(0, 3 + i * 3, format("        left %+.2f %+.2f   right %+.2f %+.2f", lx, ly, rx, ry).ljust(79), M.tattr(14))
    NAMES.each do |n, name|
      e = M.pad_pressed?(i, n) ? "pressed" : M.pad_released?(i, n) ? "released" : nil
      next unless e
      s = "pad #{i} #{name} #{e}"
      puts "PAD #{s}"
      log << s; log.shift while log.size > 8
    end
  end
  log.each_with_index { |s, k| M.text_put(0, 18 + k, s.ljust(79), M.tattr(10)) }
end
puts "PAD done"
