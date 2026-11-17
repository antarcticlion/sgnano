# S:/sbin/enfrag.rb (2026-11-02): Windows 95 風の「エンフラグ」（画面モード 7）。
# 2 クラスタ以上ある S: のファイルを、空きクラスタからランダムに選んだ所へ移して、鎖をずたずたに切り裂く。
# デフラグの試験と、地図を見て楽しむための道具。元に戻すのは defrag（S:/sbin/defrag.rb）。
# 文字はモード 7 のテキスト面ではなく、8x8 フォントをビットマップへ直接描く（実機でテキスト面が出ないため、2026-11-02）。
# キー: Enter / S = エンフラグ、R = 描き直す、Q = 終わる（ESC でも止まる）
M = Machine
SD = SystemDrive
M.mode = 7
M.text_visible = false                 # ビットマップの文字だけを使う
BM = M.bitmap
raise "no memory for the 320x200 bitmap" if BM.nil?

FONT8 = # the 8x8 font of the firmware (font128 "normal"), ' '..'~', 8 bytes a character, 1 bit a dot
  "00000000000000003030302020002000505000000000000050f8505050f850002078a07028f0200000c8d02058980000" \
  "60a040a0a890780020200000000000003040404040403000601010101010600020a8702070a82000002020f820200000" \
  "0000000000101020000000f80000000000000000000010000008102040800000708898a8c8887000206020202020f800" \
  "708808708080f800708808700888700030509090f8101000f88080f008887000708880f088887000f808102020202000" \
  "708888708888700070888878088870000030300000303000003030000030306010204080402010000000f800f8000000" \
  "402010081020400070880830200030007088a8a8b8807800708888f888888800f08888f08888f0007088808080887000" \
  "f08888888888f000f88080f08080f800f88080f080808000708880b888887800888888f8888888007020202020207000" \
  "08080808088870008890a0c0a0908800808080808080f80088d8a8888888880088c8c8a8989888007088888888887000" \
  "f08888f08080800070888888a8906800f08888f0888888007088807008887000f8202020202020008888888888887000" \
  "888888505020200088888888a8d8880088885020508888008888502020202000f80810204080f8007040404040407000" \
  "888850f820f8200070101010101070002050880000000000000000000000f80080402000000000000000689888887800" \
  "8080f0888888f0000000708880887000080878888888780000007088f8807800102020f82020200000007888887808f0" \
  "808080f08888880020002020202020000800080808080870808890a0e090880020202020202030000000f0a8a8a8a800" \
  "0000f08888888800000070888888700000b0c88888f0808000788888780808060000b8c080808000000078807008f000" \
  "2020f82020202000000088888888780000008888885020000000a8a8a8a85800000088502050880000888888780808f0" \
  "0000f8102040f80018202040202018002020200020202000c02020102020c000000040a810000000"
COLS = 32                              # 地図の横のブロック数（32 x 32 = 1,024。S: は 1,021 クラスタ）
CELL_W = 8
CELL_H = 4
MAP_X = 32
MAP_Y = 32

C_BLACK = 0
C_BLUE = 1
C_YELLOW = 6
C_GRAY = 7
C_DARK = 8
C_WHITE = 15

# 1 文字 8x8。FONT8 は ' '..'~' の 95 文字、1 文字 16 桁（8 行 x 2 桁）
def btext(x, y, text, fg = C_WHITE, bg = C_BLACK)
  i = 0
  while i < text.bytesize
    code = text.getbyte(i)
    code = 0x20 if code < 0x20 || code > 0x7e
    o = (code - 0x20) * 16
    row = 0
    while row < 8
      bits = FONT8[o + row * 2, 2].to_i(16)
      line = "\0" * 8
      col = 0
      while col < 8
        line.setbyte(col, (bits & (0x80 >> col)) != 0 ? fg : bg)
        col += 1
      end
      BM.write((y + row) * 320 + x, line)
      row += 1
    end
    x += 8
    i += 1
  end
end

def bar(row, text, fg = C_BLACK, bg = C_GRAY)
  y = row * 8
  BM.fill_rect(0, y, 320, 8, bg)
  btext(0, y, text, fg, bg)
end

def bytes_text(b)
  if b >= 1024 * 1024
    format("%d.%d MB", b / (1024 * 1024), (b % (1024 * 1024)) * 10 / (1024 * 1024))
  else
    format("%d KB", (b + 1023) / 1024)
  end
end

def progress_text(done, total)
  pct = total > 0 ? done * 100 / total : 100
  pct = 100 if pct > 100
  n = pct * 20 / 100
  "[" + ("#" * n) + ("-" * (20 - n)) + "] #{pct}%"
end

def draw_map
  map = SD.map
  return unless map
  BM.fill_rect(MAP_X, MAP_Y, COLS * CELL_W, COLS * CELL_H, C_BLACK)
  rows = (map.bytesize + COLS - 1) / COLS
  r = 0
  while r < rows
    last = map.bytesize - r * COLS
    last = COLS if last > COLS
    x = 0
    while x < last
      v = map.getbyte(r * COLS + x)
      x2 = x + 1
      x2 += 1 while x2 < last && map.getbyte(r * COLS + x2) == v
      color = v == 0 ? C_WHITE : C_BLUE
      BM.fill_rect(MAP_X + x * CELL_W, MAP_Y + r * CELL_H, (x2 - x) * CELL_W - 1, CELL_H - 1, color)
      x = x2
    end
    r += 1
  end
end

def draw_chrome(title)
  BM.fill_rect(0, 0, 320, 200, C_GRAY)
  BM.fill_rect(0, 0, 320, 8, C_BLUE)
  BM.fill_rect(MAP_X - 2, MAP_Y - 2, COLS * CELL_W + 4, 1, C_WHITE)
  BM.fill_rect(MAP_X - 2, MAP_Y - 2, 1, COLS * CELL_H + 4, C_WHITE)
  BM.fill_rect(MAP_X - 2, MAP_Y + COLS * CELL_H + 1, COLS * CELL_W + 4, 1, C_DARK)
  BM.fill_rect(MAP_X + COLS * CELL_W + 1, MAP_Y - 2, 1, COLS * CELL_H + 4, C_DARK)
  bar(0, " #{title}", C_WHITE, C_BLUE)
  btext(296, 0, "[X]", C_WHITE, C_BLUE)
  bar(1, " File  View  Help", C_BLACK, C_GRAY)
  bar(2, " Drive: [ S: System (4 MB) ]", C_BLACK, C_GRAY)
  bar(3, " Cluster map  (1 block = 4 KB)", C_BLACK, C_GRAY)
end

def draw_legend
  bar(20, "  Legend:", C_BLACK, C_GRAY)
  BM.fill_rect(80, 160, 32, 8, C_BLUE); btext(80, 160, "Used", C_WHITE, C_BLUE)
  BM.fill_rect(128, 160, 32, 8, C_WHITE); btext(128, 160, "Free", C_BLACK, C_WHITE)
  BM.fill_rect(176, 160, 56, 8, C_YELLOW); btext(176, 160, "Working", C_BLACK, C_YELLOW)
  btext(240, 160, "4KB block", C_BLACK, C_GRAY)
end

def draw_buttons
  bar(22, "  [ Start ]  [ Refresh ]  [ Quit ]", C_BLACK, C_GRAY)
end

def draw_idle
  draw_chrome("Enfrag - S:")
  draw_map
  draw_legend
  free = SD.free_bytes
  used = SD.clusters - SD.free_clusters
  bar(21, "  Progress  [--------------------]   0%", C_BLACK, C_GRAY)
  draw_buttons
  bar(23, "  Ready  #{bytes_text(free)} free  #{used} used", C_BLACK, C_GRAY)
  bar(24, "  Enter/S: split  R  Q  (defrag)", C_BLACK, C_GRAY)
end

def draw_working(what, done, total, files_done, files)
  # S: を書いている間は表示面を C 側で隠している。ここでは次の表示に備えてビットマップを更新するだけ
  bar(0, " #{what}", C_WHITE, C_BLUE)
  bar(1, " File  View  Help", C_BLACK, C_GRAY)
  bar(2, " Drive: [ S: System (4 MB) ]", C_BLACK, C_GRAY)
  bar(3, " Cluster map  (1 block = 4 KB)", C_BLACK, C_GRAY)
  bar(21, "  Progress  #{progress_text(done, total)}", C_BLACK, C_GRAY)
  bar(22, "  Working...  Q: stop", C_BLACK, C_GRAY)
  bar(23, "  #{done}/#{total} cl  #{files_done}/#{files} files", C_BLACK, C_GRAY)
  bar(24, "  Scattering...  Do not power off.", C_BLACK, C_GRAY)
end

def dialog(title, line)
  BM.fill_rect(38, 62, 246, 58, C_DARK)
  BM.fill_rect(36, 60, 246, 56, C_GRAY)
  BM.fill_rect(36, 60, 246, 1, C_WHITE)
  BM.fill_rect(36, 60, 1, 56, C_WHITE)
  BM.fill_rect(36, 115, 246, 1, C_DARK)
  BM.fill_rect(281, 60, 1, 56, C_DARK)
  BM.fill_rect(36, 60, 246, 10, C_BLUE)
  btext(38, 61, title, C_WHITE, C_BLUE)
  btext(40, 76, line, C_BLACK, C_GRAY)
  btext(136, 100, "[ OK ]", C_BLACK, C_GRAY)
  M.wait_key
  M.clear_keys
end

def stop_key?
  k = M.key
  k == "q".ord || k == "Q".ord
end

def run_enfrag
  r = nil
  8.times do
    r = SD.enfrag_start
    break if r
    M.vsync
  end
  if r.nil?
    dialog("Enfrag", "Could not start (busy/memory).")
    draw_idle
    return
  end
  files = r[0]
  total = r[1]
  # 表示は C 側で隠れている。終わったら draw_idle で地図を出す
  loop do
    p = SD.enfrag_step
    break if p.nil?
    done, all, dfiles, afiles, fin = p
    if fin
      puts "ENFRAG COMPLETE #{done}/#{all} clusters"
      draw_idle
      dialog("Fragmentation Complete", "2+ cluster files scattered.")
      break
    end
    if stop_key?
      SD.abort
      draw_idle
      break
    end
    M.vsync
  end
  draw_idle
end

M.clear_keys
draw_idle
loop do
  k = M.key
  case k
  when 13, "s".ord, "S".ord
    run_enfrag
  when "r".ord, "R".ord
    draw_idle
  when "q".ord, "Q".ord
    break
  end
  M.vsync
end
SD.abort
M.text_visible = true
M.text_clear
puts "ENFRAG done"
