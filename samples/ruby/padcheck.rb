# Checks of the pad helpers (2026-10-18). On the host, scripts/test_mruby.py feeds pad 0 with RBM_PAD_SEQ
# (one entry a frame: hat,buttons,x,y,z,rz). Prints "padcheck: all ok" at the end.
$ng = 0
def ok(cond, what)
  return if cond
  puts "NG #{what}"
  $ng += 1
end
M = Machine
M.pad_update                                  # frame 0: nothing pressed, hat neutral, sticks centered
ok !M.pad_button?(0, M::PAD_A), "A up at first"
M.vsync                                       # frame 1: A (button 2) down, hat up
ok M.pad_button?(0, M::PAD_A), "A down"
ok M.pad_pressed?(0, M::PAD_A), "A pressed edge"
ok M.pad_pressed?(0, M::PAD_UP), "up pressed edge (hat)"
ok M.pad_dir(0) == [0, -1], "dir up #{M.pad_dir(0)}"
M.vsync                                       # frame 2: A still down, hat right-down
ok M.pad_button?(0, M::PAD_A) && !M.pad_pressed?(0, M::PAD_A), "A held, no edge"
ok M.pad_released?(0, M::PAD_UP), "up released"
ok M.pad_dir(0) == [1, 1], "dir right-down #{M.pad_dir(0)}"
M.vsync                                       # frame 3: A up, left stick full left, right stick (Z/Rz) half right / up
ok M.pad_released?(0, M::PAD_A), "A released edge"
ok M.pad_dir(0) == [-1, 0], "dir from the left stick #{M.pad_dir(0)}"
x, y = M.pad_stick(0, :left)
ok x == -1.0 && y == 0.0, "left stick #{[x, y]}"
rx, ry = M.pad_stick(0, :right)
ok rx > 0.3 && rx < 0.5 && ry < -0.3 && ry > -0.5, "right stick #{[rx, ry]}"
ok M.pad_axis(0, 0) == -1.0 && M.pad_axis(0, 1) == 0.0, "axis"
ok M.pad_axis(0, 2, 0.9) == 0.0, "dead zone"
ok M.pad_axis(0, 3) == 0.0, "missing axis is 0.0"
ok !M.pad_button?(1, M::PAD_A) && M.pad_dir(1) == [0, 0], "pad 1 not connected"
begin; M.pad_button?(4, 1); ok false, "pad 4 raises"; rescue ArgumentError; end
begin; M.pad_button?(0, 33); ok false, "button 33 raises"; rescue ArgumentError; end
puts $ng == 0 ? "padcheck: all ok" : "padcheck: #{$ng} NG"
