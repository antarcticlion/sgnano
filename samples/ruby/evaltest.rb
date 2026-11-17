# evaltest.rb: check eval / binding / instance_eval / class_eval (mruby-eval, mruby-binding,
# mruby-proc-binding, added 2026-10-25). Prints "ok" lines and "eval: all ok".
$ng = 0
def check(name, got, want)
  if got == want
    puts "ok   #{name}"
  else
    puts "NG   #{name}: got #{got.inspect}, want #{want.inspect}"
    $ng += 1
  end
end

check "eval number", eval("1 + 2 * 3"), 7
check "eval string", eval("'ab' * 3"), "ababab"
x = 10
check "eval sees locals", eval("x * 2"), 20
eval("x = 42")
check "eval sets locals", x, 42

b = binding
y = 5
check "binding local_variable_get", b.local_variable_get(:y), 5
b.local_variable_set(:y, 6)
check "binding local_variable_set", y, 6
check "binding local_variable_defined?", b.local_variable_defined?(:y), true
check "binding eval", b.eval("x + y"), 48
check "eval with binding", eval("y * 10", b), 60

def make_counter
  n = 0
  binding
end
cb = make_counter
cb.eval("n += 1")
cb.eval("n += 1")
check "binding keeps its frame", cb.local_variable_get(:n), 2
check "binding receiver", binding.receiver, self

pr = proc { |q| q }
z = 7
check "Proc#binding", pr.binding.local_variable_get(:z), 7

class Box
  def initialize
    @v = 3
  end
end
bx = Box.new
check "instance_eval string", bx.instance_eval("@v * 2"), 6
check "instance_eval block", bx.instance_eval { @v + 1 }, 4
Box.class_eval("def twice; @v * 2; end")
check "class_eval string", bx.twice, 6
Box.class_eval { def thrice; @v * 3; end }
check "class_eval block", bx.thrice, 9

begin
  eval("1 +")
  check "SyntaxError", "no error", "SyntaxError"
rescue SyntaxError => e
  check "SyntaxError", e.class, SyntaxError
end

src = "def sq(v) = v * v\n[1, 2, 3].map { |i| sq(i) }"
check "eval defines a method", eval(src), [1, 4, 9]
sum = 0
100.times { |i| sum += eval("#{i} + 1") }
check "eval in a loop (100)", sum, 5050

puts $ng == 0 ? "eval: all ok" : "eval: #{$ng} NG"
