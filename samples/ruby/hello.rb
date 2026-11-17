# sgnano で動く mruby/c のサンプル（2026-10-11）
puts "Hello, sgnano! こんにちは"
a = [3, 1, 2].sort.map { |x| x * 10 }
p a
h = { name: "sgnano", cpu: "RP2350", mhz: 302.4 }
h.each { |k, v| puts "#{k}: #{v}" }
def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)
puts "fib(20) = #{fib(20)}"
puts "Math.sqrt(2) = #{Math.sqrt(2.0)}"
