# 追加 gem の確認（2026-11-02）: Data、Enumerator::Lazy、Enumerator::Chain、JSON
Point = Data.define(:x, :y)
p = Point.new(1, 2)
raise "Data x" unless p.x == 1 && p.y == 2
raise "Data to_h" unless p.to_h == { x: 1, y: 2 }
raise "Data inspect" unless p.inspect == "#<data Point x=1, y=2>"
raise "Data ==" unless p == Point.new(1, 2)

lazy = (1..1_000_000).lazy.select { |n| (n % 3).zero? }.map { |n| n * 2 }.first(4)
raise "Lazy #{lazy.inspect}" unless lazy == [6, 12, 18, 24]
chain = [1, 2].chain([3, 4])
raise "Chain #{chain.to_a.inspect}" unless chain.to_a == [1, 2, 3, 4]
raise "Chain +" unless (chain + [5]).to_a == [1, 2, 3, 4, 5]

obj = { "a" => 1, "b" => [true, nil, "x\n\"y\""], "c" => 3.5 }
json = JSON.generate(obj)
back = JSON.parse(json)
raise "JSON a" unless back["a"] == 1
raise "JSON b" unless back["b"][0] == true && back["b"][1].nil? && back["b"][2] == "x\n\"y\""
raise "JSON c" unless (back["c"] - 3.5).abs < 0.0001
raise "JSON pretty" unless JSON.pretty_generate(obj).include?("\n")
raise "JSON load" unless JSON.load('{"n": 123}')["n"] == 123

# Bignum / Rational / Complex / CMath（2026-11-02）
raise "Bignum" unless (2 ** 100).to_s == "1267650600228229401496703205376"
r = Rational(4, 10)
raise "Rational class" unless r.class == Rational
raise "Rational reduce" unless r.numerator == 2 && r.denominator == 5
raise "Rational +" unless Rational(1, 2) + Rational(1, 3) == Rational(5, 6)
raise "Rational to_f" unless (r.to_f - 0.4).abs < 1e-9
c = Complex(1, 2)
raise "Complex class" unless c.class == Complex && c.real == 1 && c.imaginary == 2
raise "Complex +" unless Complex(1, 2) + Complex(3, -1) == Complex(4, 1)
raise "Complex *" unless Complex(1, 2) * Complex(3, 4) == Complex(-5, 10)
raise "Complex abs" unless (Complex(3, 4).abs - 5.0).abs < 1e-9
z = CMath.sqrt(-4.0)
raise "CMath sqrt" unless z.real.abs < 1e-9 && (z.imaginary - 2.0).abs < 1e-9
raise "CMath exp" unless (CMath.exp(0) - 1.0).abs < 1e-9
raise "strftime" unless Time.local(2026, 11, 2, 12, 34, 56).strftime("%Y-%m-%d %H:%M:%S") == "2026-11-02 12:34:56"
puts "gems2: all ok"
