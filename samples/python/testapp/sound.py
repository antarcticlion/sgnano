# Sound の見本（MicroPython 版、2026-10-30）。samples/ruby/sound.rb から移植。
# 前半はポートを直接（音階とエンベロープ）、後半はシーケンサーで WTF4CH.mid を流す。
# キー: Space 一時停止・再開、+ / - 速さ、e 効果音のフレーズ（ポート 3 を占有）、r 頭から、q 終わり。
import math
print("Sound: %d channels" % Sound.channels)

# ---- 前半: ポート 0 で音階（矩形波、短いアタック・長めのリリース）----
Sound.wave(0, Sound.SQUARE)
Sound.adsr(0, 0, 40, 90, 50)
Sound.volume(0, 100)
for n in (60, 62, 64, 65, 67, 69, 71, 72):
    Sound.note_on(0, n, 110)
    M.vsync(6)
    print("note %3d  phase %-8s level %3d" % (n, Sound.phase(0), Sound.level(0)))
    Sound.note_off(0)
    M.vsync(6)
M.vsync(30)
print("release: phase %s level %d" % (Sound.phase(0), Sound.level(0)))

# GM の音色（プログラム）を当てて和音（ポート 0..2）
Sound.program(0, 48); Sound.program(1, 48); Sound.program(2, 48)
for i, n in enumerate((60, 64, 67)):
    Sound.note_on(i, n, 90)
M.vsync(90)
for i in range(3):
    Sound.note_off(i)
M.vsync(60)

# ---- ノイズ（4ch 目のドラム。RNG から作った波形を WT と同じ音程・EG で）----
Sound.set_mode(3, Sound.NOISE_MODE)
Sound.adsr(3, 0, 18, 0, 12)
Sound.volume(3, 110)
for n in (48, 45, 41):
    Sound.note_on(3, n, 127)
    M.vsync(4)
    Sound.note_off(3)
    M.vsync(6)
Sound.set_mode(3, Sound.WT)

# ---- PCM（Paula 風の 32 サンプル）とパン ----
pcm = bytes([int(math.sin(i * 2 * math.pi / 32) * 100) & 0xFF for i in range(32)])
Sound.set_mode(0, Sound.PCM)
Sound.pcm(0, pcm)
Sound.adsr(0, 0, 30, 100, 40)
Sound.volume(0, 110)
Sound.pan(0, 0)                 # 左
Sound.note_on(0, 69, 100)
M.vsync(30)
Sound.pan(0, 127)               # 右
M.vsync(30)
Sound.note_off(0)
M.vsync(30)
Sound.set_mode(0, Sound.WT)
Sound.pan(0, 64)                # 中央

# ---- 後半: シーケンサー ----
# 効果音のフレーズ（SMF のフォーマット 0 を bytes で組む: 上がっていく 3 音）
def smf0(events):
    trk = events + b"\x00\xff\x2f\x00"
    return b"MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60" + b"MTrk" + len(trk).to_bytes(4, "big") + trk
SFX = smf0(b"\x00\xc0\x50" + b"\x00\x90\x48\x7f" + b"\x18\x80\x48\x00" + b"\x00\x90\x4c\x7f" + b"\x18\x80\x4c\x00" +
           b"\x00\x90\x4f\x7f" + b"\x30\x80\x4f\x00")

song = "WTF4CH.mid"
if not File.exist(song):
    song = "A:/WTF4CH.mid"
Sound.play(song)
print("playing %s: %.1f s" % (song, Sound.length() / 1000.0))
tempo = 100
last = -1
while Sound.playing():
    k = M.key()
    if k == 32:
        Sound.resume() if Sound.paused() else Sound.pause()
    elif k == 43:                                        # +
        tempo = min(tempo + 10, 400); Sound.tempo(tempo)
    elif k == 45:                                        # -
        tempo = max(tempo - 10, 25); Sound.tempo(tempo)
    elif k == 101:                                       # e
        Sound.sfx(SFX, 3)
    elif k == 114:                                       # r
        Sound.play(song)
    elif k == 113:                                       # q
        break
    s = Sound.position() // 1000
    if s != last:
        last = s
        print("%3d / %d s  tempo %d%%%s%s" % (s, Sound.length() // 1000, tempo,
              "  (paused)" if Sound.paused() else "", "  sfx" if Sound.sfx_playing(3) else ""))
    M.vsync()
Sound.stop()
print("done")
