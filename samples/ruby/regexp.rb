# Regexp (Onigmo) checks (2026-10-28). Light enough to run on the device too.
bad = false
check = ->(name, ok) { puts((ok ? "ok  " : "NG  ") + name); bad = true unless ok }

re = Regexp.new("a(b+)c")
m = re.match("xxabbbcyy")
check.call("match", !m.nil? && m[0] == "abbbc" && m[1] == "bbb")
check.call("begin/end", m.begin(0) == 2 && m.end(0) == 7)
check.call("pre/post", m.pre_match == "xx" && m.post_match == "yy")
check.call("captures", m.captures == ["bbb"] && m.to_a == ["abbbc", "bbb"] && m.size == 2)
check.call("regexp", m.regexp == re)
check.call("=~", (re =~ "abbbc") == 0 && (re =~ "zzz").nil?)
check.call("last_match", (re =~ "xxabbbc") == 2 && Regexp.last_match[0] == "abbbc")
check.call("match?", Regexp.new("b+").match?("abbbc") && !Regexp.new("b+").match?("ccc"))
check.call("scan", "a1b22".scan(Regexp.new("\\d+")) == ["1", "22"])
check.call("gsub", "a1b22".gsub(Regexp.new("\\d+"), "#") == "a#b#")
check.call("sub", "a1b22".sub(Regexp.new("\\d+"), "#") == "a#b22")
check.call("split", "a,b,,c".split(Regexp.new(",")) == ["a", "b", "", "c"])

named = Regexp.new("(?<year>\\d{4})-(?<month>\\d{2})").match("2026-10")
check.call("named", named["year"] == "2026" && named["month"] == "10")
check.call("names", named.names.sort == ["month", "year"])
check.call("ignorecase", Regexp.new("abc", Regexp::IGNORECASE).match?("ABC"))
check.call("utf8", !(Regexp.new("こ+") =~ "あここ").nil?)
check.call("escape", Regexp.escape("a.b") == "a\\.b")
check.call("alternation", Regexp.new("a|b").match?("b"))
check.call("version", !Regexp.version.nil?)

begin
  Regexp.new("[")
  check.call("syntax error", false)
rescue RegexpError
  check.call("syntax error", true)
end

puts(bad ? "regexp: NG" : "regexp: all ok")
