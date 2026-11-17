# PCM とパンの短い見本（2026-10-30、SPEC_sound.md）。実機で音と例外の有無を見る
puts "Sound: #{Sound.channels} channels"
pcm = (0...32).map { |i| (Math.sin(i * 2 * Math::PI / 32) * 100).to_i }.pack("c*")
puts "pcm bytes #{pcm.bytesize}"
Sound.set_mode(2, Sound::PCM)
Sound.pcm(2, pcm)
Sound.adsr(2, 0, 30, 110, 40)
Sound.volume(2, 110)
Sound.pan(2, 0)
Sound.note_on(2, 69, 100)
Machine.vsync(20)
puts format("left   mode=%d phase=%s level=%d", Sound.mode(2), Sound.phase(2), Sound.level(2))
Sound.pan(2, 64)
Machine.vsync(20)
Sound.pan(2, 127)
Machine.vsync(20)
puts format("right  mode=%d phase=%s level=%d", Sound.mode(2), Sound.phase(2), Sound.level(2))
Sound.note_off(2)
Machine.vsync(20)
puts format("off    mode=%d phase=%s level=%d", Sound.mode(2), Sound.phase(2), Sound.level(2))
Sound.set_mode(2, Sound::WT)
Sound.pan(2, 64)
puts "done"
