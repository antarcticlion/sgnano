# Speed table for docs/sgnano_ruby_guide.md section 9 (2026-10-18).
# Runs the same items in screen mode 1 (no FB), 2 (RGB555 FB shown) and 4 (CLUT4 FB shown).
def t(label)
  t0 = Machine.ms
  yield
  ms = Machine.ms - t0
  puts "BENCH #{Machine.mode} #{label}: #{ms} ms"
end

[1, 2, 4].each do |m|
  Machine.mode = m
  t("while 100k") { i = 0; while i < 100000; i += 1; end }
  next if m == 1
  fb = Machine.fb
  c = m == 4 ? 7 : Machine.rgb(31, 31, 0)
  t("pset 10k") { 10000.times { |i| fb.pset(i % 640, (i / 640) % 480, c) } }
  t("fill_rect 64x48 1000") { 1000.times { |i| fb.fill_rect((i * 7) % 576, (i * 5) % 432, 64, 48, c) } }
  t("line full 1000") { 1000.times { |i| fb.line(0, 0, 639, i % 480, c) } }
  t("fill_triangle 64x48 1000") { 1000.times { |i| x = (i * 7) % 576; y = (i * 5) % 432; fb.fill_triangle(x, y, x + 63, y, x, y + 47, c) } }
  t("fill_triangle full 100") { 100.times { fb.fill_triangle(0, 0, 639, 0, 0, 479, c) } }
  t("triangle 1000") { 1000.times { fb.triangle(0, 0, 639, 240, 100, 479, c) } }
  t("blit 64x48 1000") { 1000.times { |i| fb.blit(0, 0, 64, 48, (i * 7) % 576, (i * 5) % 432) } }
  t("blit 64x48 key 1000") { 1000.times { |i| fb.blit(0, 0, 64, 48, (i * 7) % 576, (i * 5) % 432, nil, 0) } }
  s = nil
  t("get_block 64x48 1000") { 1000.times { s = fb.get_block(0, 0, 64, 48) } }
  t("put_block 64x48 1000") { 1000.times { |i| fb.put_block((i * 7) % 576, (i * 5) % 432, 64, 48, s) } }
  t("clear 100") { 100.times { fb.clear(0) } }
end
Machine.mode = 1
puts "BENCH done"
