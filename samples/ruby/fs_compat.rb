# File I/O compatibility and stability test (sgnano, 2026-10-16).
# Uses only paths relative to the current folder, so CRuby can run it too: the output is compared with CRuby's.
# Works in the folder "fsct" and removes it at the end.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue Exception => e
  puts "#{name}: raised #{e.class}"
end

def crc(s)
  c = 0
  s.each_byte { |b| c = (c * 31 + b) % 1000003 }
  c
end

Dir.mkdir("fsct") unless File.directory?("fsct")
Dir.chdir("fsct")

# --- text ---
t("write") { File.write("a.txt", "one\ntwo\nthree\n") }
t("read") { File.read("a.txt") }
t("append") { File.open("a.txt", "a") { |f| f.print "four", "\n"; f.puts "five" } }
t("readlines") { File.readlines("a.txt") }
t("foreach") { r = []; File.foreach("a.txt") { |l| r << l.chomp }; r }
t("gets sep") { File.open("a.txt") { |f| [f.gets, f.gets("e"), f.gets(nil)] } }
t("getc getbyte") { File.open("a.txt") { |f| [f.getc, f.getbyte, f.getc] } }
t("read n") { File.open("a.txt") { |f| [f.read(3), f.read(0), f.read(100).size, f.read(1)] } }
t("eof") { File.open("a.txt") { |f| a = f.eof?; f.read; [a, f.eof?] } }
t("seek pos") { File.open("a.txt") { |f| f.seek(4); a = f.read(3); f.seek(-5, IO::SEEK_END); [a, f.pos, f.read] } }
t("rewind") { File.open("a.txt") { |f| f.read; f.rewind; [f.pos, f.gets] } }
t("each_line") { r = []; File.open("a.txt") { |f| f.each_line { |l| r << l.size } }; r }
t("size") { [File.size("a.txt"), File.open("a.txt") { |f| f.size }] }

# --- modes ---
t("w truncates") { File.write("b.txt", "long contents"); File.write("b.txt", "x"); File.read("b.txt") }
t("r+ overwrite") { File.write("c.txt", "abcdef"); File.open("c.txt", "r+") { |f| f.seek(2); f.write("XY") }; File.read("c.txt") }
t("w+ read back") { File.open("d.txt", "w+") { |f| f.write("hello"); f.rewind; f.read } }
t("a+ read") { File.write("e.txt", "123"); File.open("e.txt", "a+") { |f| f.write("45"); f.rewind; f.read } }

# --- binary ---
bin = ""
256.times { |i| bin << i.chr }
t("binwrite") { File.binwrite("f.bin", bin) }
t("binread") { b = File.binread("f.bin"); [b.size, b.getbyte(0), b.getbyte(255), crc(b)] }

# --- names and folders ---
t("exist") { [File.exist?("a.txt"), File.file?("a.txt"), File.directory?("."), File.exist?("nope")] }
t("rename") { File.rename("b.txt", "b2.txt"); [File.exist?("b.txt"), File.read("b2.txt")] }
t("mkdir") { Dir.mkdir("sub") }
t("write in sub") { File.write("sub/x.txt", "deep") }
t("children") { Dir.children(".").sort }
t("entries") { Dir.entries("sub").sort }
t("chdir block") { Dir.chdir("sub") { File.read("x.txt") } }
t("pwd back") { File.basename(Dir.pwd) }
t("basename") { [File.basename("x/y/z.rb"), File.basename("z.rb", ".rb"), File.basename("a/b.tar.gz", ".*")] }
t("dirname extname") { [File.dirname("x/y/z.rb"), File.dirname("z.rb"), File.extname("z.tar.gz"), File.extname(".bashrc")] }
t("join") { [File.join("a", "b"), File.join("a/", "/b"), File.join("a", ["b", "c"])] }
t("expand") { File.basename(File.expand_path("sub/../a.txt")) }
t("unicode name") { File.write("\u65E5\u672C.txt", "jp"); [File.read("\u65E5\u672C.txt"), Dir.children(".").include?("\u65E5\u672C.txt")] }

# --- attributes and times (2026-10-16) ---
t("stat") { s = File.stat("a.txt"); [s.size, s.file?, s.directory?, s.size?, s.ftype, File.stat(".").directory?] }
t("stat zero") { File.write("z.txt", ""); [File.stat("z.txt").zero?, File.stat("z.txt").size?] }
t("mtime") { m = File.mtime("a.txt"); [m.class, File.stat("a.txt").mtime == m, m.year >= 2026, File.open("a.txt") { |f| f.mtime.class }] }
t("chmod") do
  File.chmod(0444, "c.txt")
  a = [File.writable?("c.txt"), File.stat("c.txt").writable?, File.stat("c.txt").mode & 0222]
  File.chmod(0644, "c.txt")
  a + [File.writable?("c.txt"), File.stat("c.txt").mode & 0200]
end
t("write read-only") do
  File.chmod(0444, "e.txt")
  r = begin
    File.write("e.txt", "x")
  rescue SystemCallError => e
    e.class
  end
  File.chmod(0644, "e.txt")
  [r, File.read("e.txt")]
end
t("time local") { t = Time.local(2026, 10, 16, 10, 2, 4); [t.year, t.month, t.day, t.hour, t.min, t.sec, t.wday, t.yday] }
t("strftime") { Time.local(2026, 1, 5, 7, 8, 9).strftime("%Y-%m-%d %H:%M:%S %a %b %j %y %e %-d %I %p %%") }
t("time arith") { t = Time.local(2026, 12, 31, 23, 59, 59); [(t + 1).strftime("%F %T"), (t + 1) - t, t - 86400 < t, (t <=> t + 1)] }
t("time at") { [Time.at(100) - Time.at(40), Time.at(1.5).usec, Time.at(7) == Time.at(7), Time.at(0).class] }

# --- errors ---
t("open missing") { File.open("nope.txt") }
t("read missing") { File.read("nope.txt") }
t("mkdir exists") { Dir.mkdir("sub") }
t("rmdir not empty") { Dir.rmdir("sub") }
t("delete folder") { File.delete("sub") }
t("rmdir file") { Dir.rmdir("a.txt") }
t("chdir missing") { Dir.chdir("nope") }
t("read closed") { f = File.open("a.txt"); f.close; f.read }
t("write closed") { f = File.open("a.txt", "a"); f.close; f.write("x") }
t("write read-only") { File.open("a.txt") { |f| f.write("x") } }
t("read write-only") { File.open("w.txt", "w") { |f| f.read } }
t("close twice") { f = File.open("a.txt"); f.close; f.close; f.closed? }
t("bad mode") { File.open("a.txt", "q") }
t("exception in block") do
  begin
    File.open("g.txt", "w") { |f| f.write("kept"); raise "boom" }
  rescue RuntimeError
  end
  File.read("g.txt")
end

# --- output ---
t("puts value") { $stdout.puts("out 1") }
t("print value") { print("out 2\n") }
t("p value") { p(1, 2) }
puts [1, [2, 3]]
puts nil
puts
print "a", "b", "\n"

# --- size and count ---
big = "0123456789abcdef" * 20000
t("write 320KB") { File.write("big.bin", big) }
t("read 320KB") { s = File.read("big.bin"); [s.size, crc(s) == crc(big)] }
t("1000 appends") { File.open("h.txt", "w") { |f| 1000.times { |i| f.write("#{i}\n") } }; File.readlines("h.txt").size }
t("8 open") { fs = []; 8.times { |i| fs << File.open("o#{i}.txt", "w") }; fs.each { |f| f.write("x"); f.close }; Dir.children(".").count { |n| n.start_with?("o") } }

# --- clean up ---
Dir.children(".").each { |n| File.directory?(n) ? (Dir.children(n).each { |m| File.delete("#{n}/#{m}") }; Dir.rmdir(n)) : File.delete(n) }
Dir.chdir("..")
Dir.rmdir("fsct")
t("cleaned") { File.exist?("fsct") }
puts "done"
