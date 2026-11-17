# gems.rb: check Set, Method / UnboundMethod, ObjectSpace (mruby-set, mruby-method,
# mruby-objectspace, mruby-os-memsize, added 2026-10-25). Prints "ok" lines and "gems: all ok".
$ng = 0
def check(name, got, want)
  if got == want
    puts "ok   #{name}"
  else
    puts "NG   #{name}: got #{got.inspect}, want #{want.inspect}"
    $ng += 1
  end
end

# --- Set ---
s = Set.new([3, 1, 3, 2])
check "Set dedup size", s.size, 3
check "Set include?", s.include?(2), true
s << 5
s.delete(1)
check "Set add/delete", s.to_a.sort, [2, 3, 5]
check "Set add? (new)", !!s.add?(7), true
check "Set add? (dup)", s.add?(7), nil
a = Set[1, 2, 3]
b = Set[2, 3, 4]
check "Set |", (a | b).to_a.sort, [1, 2, 3, 4]
check "Set &", (a & b).to_a.sort, [2, 3]
check "Set -", (a - b).to_a, [1]
check "Set ^", (a ^ b).to_a.sort, [1, 4]
check "Set subset?", a.subset?(Set[1, 2, 3, 4]), true
check "Set superset?", Set[1, 2, 3, 4].superset?(a), true
check "Set disjoint?", a.disjoint?(Set[7, 8]), true
check "Set ==", Set[1, 2] == Set[2, 1], true
check "Set map", a.map { |x| x * 10 }.sort, [10, 20, 30]
check "Set.new(array)", Set.new([1, 1, 2]).size, 2   # mruby has no Array#to_set
pos = Set.new
pos << [3, 4]
check "Set of arrays", pos.include?([3, 4]), true
check "Set classify", Set[1, 2, 3, 4].classify(&:even?)[true].to_a.sort, [2, 4]

# --- Method ---
class Greeter
  def initialize(n)
    @n = n
  end

  def hello(who)
    "#{@n}: hello #{who}"
  end
end
g = Greeter.new("sg")
m = g.method(:hello)
check "Method#call", m.call("nano"), "sg: hello nano"
check "Method#arity", m.arity, 1
check "Method#name", m.name, :hello
check "Method#owner", m.owner, Greeter
check "Method#receiver", m.receiver.equal?(g), true
check "Method#to_proc", ["a", "b"].map(&g.method(:hello)), ["sg: hello a", "sg: hello b"]
um = Greeter.instance_method(:hello)
check "UnboundMethod#bind", um.bind(Greeter.new("x")).call("y"), "x: hello y"
check "Method#unbind", m.unbind.bind_call(Greeter.new("z"), "w"), "z: hello w"
check "Method#>>", (5.method(:+) >> ->(v) { v * 2 }).call(1), 12
check "Method#parameters", m.parameters, [[:req, :who]]

# --- ObjectSpace ---
c = ObjectSpace.count_objects
check "count_objects Hash", c.is_a?(Hash), true
check "count_objects TOTAL", c[:TOTAL] > 0, true
n = 0
ObjectSpace.each_object(Greeter) { n += 1 }
check "each_object(Greeter)", n >= 1, true
check "memsize_of String", ObjectSpace.memsize_of("x" * 1000) >= 1000, true
check "memsize_of_all", ObjectSpace.memsize_of_all > 0, true

puts "objects: #{c[:TOTAL]} total, #{c[:FREE]} free"
puts $ng == 0 ? "gems: all ok" : "gems: #{$ng} NG"
