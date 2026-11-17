# Pen tablet (Wacom Graphire4 / Bamboo, 2026-10-23): draw with the pen, the pressure sets the size.
# The eraser (the back of the pen) erases. Pad button 1 clears the page, pad button 2 changes the color,
# the wheel changes the size. The pen buttons pick the color too (1 = red, 2 = blue). q ends it (ESC also stops).
M = Machine
M.mode = 2
fb = M.fb
fb.clear
colors = [M.rgb(255, 255, 255), M.rgb(255, 80, 80), M.rgb(80, 160, 255), M.rgb(120, 255, 120), M.rgb(255, 220, 60)]
ci = 0
size = 6
last = nil
pad_was = 0
M.text_clear
loop do
  break if M.key == "q".ord
  M.vsync
  t = M.tablet
  unless t[:connected]
    M.text_put(0, 0, "no tablet -- plug a Wacom Graphire / Bamboo in".ljust(79), M.tattr(14))
    next
  end
  pad = t[:pad]
  if (pad & 1) != 0 && (pad_was & 1) == 0
    fb.clear
    last = nil
  end
  ci = (ci + 1) % colors.size if (pad & 2) != 0 && (pad_was & 2) == 0
  pad_was = pad
  size = [[6 + t[:wheel], 1].max, 30].min
  x = t[:x] * 640 / t[:x_max]
  y = t[:y] * 480 / t[:y_max]
  if t[:proximity] && t[:tip]
    r = 1 + size * t[:pressure] / t[:pressure_max]
    color = t[:tool] == :eraser ? 0 : t[:button1] ? colors[1] : t[:button2] ? colors[2] : colors[ci]
    r = size * 2 if t[:tool] == :eraser
    if last
      # 前の点からいまの点まで、間を埋める
      n = [(x - last[0]).abs, (y - last[1]).abs, 1].max / [r / 2, 1].max
      n = 1 if n < 1
      n.times do |k|
        px = last[0] + (x - last[0]) * (k + 1) / n
        py = last[1] + (y - last[1]) * (k + 1) / n
        fb.fill_rect(px - r / 2, py - r / 2, r, r, color)
      end
    else
      fb.fill_rect(x - r / 2, y - r / 2, r, r, color)
    end
    last = [x, y]
  else
    last = nil
  end
  tool = t[:proximity] ? t[:tool].to_s : "-"
  M.text_put(0, 0, format("%s %s  tool %-6s x %5d y %5d  pressure %3d  tip %d b1 %d b2 %d  pad %d  wheel %+d  size %d",
                          t[:name], t[:ready] ? "ready" : "(switching)", tool, t[:x], t[:y], t[:pressure],
                          t[:tip] ? 1 : 0, t[:button1] ? 1 : 0, t[:button2] ? 1 : 0, pad, t[:wheel], size).ljust(79), M.tattr(15))
end
M.text_clear
puts "TABLET done"
