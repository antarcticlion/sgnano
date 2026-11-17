# Kernel#system（2026-11-03）。コマンドを sgsh の 1 行実行で走らせ、終了番号 0 なら true、それ以外は false。
raise "system true" unless system("true") == true
raise "system false" unless system("false") == false
raise "system echo" unless system("echo system-ok") == true
raise "system not found" unless system("no-such-command-sgnano") == false
puts "system: all ok"
