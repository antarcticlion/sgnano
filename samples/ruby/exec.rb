# Kernel#exec（2026-11-03）。コマンドを走らせ、その終了番号で mruby を終える。
# ここでは 3 で終わるので、呼び手（sgsh / ファイラー）は 3 を受け取る。
puts "exec-before"
exec("exit 3")
puts "exec-after"   # ここには来ない
