# File I/O test (sgnano). Uses the folder "rbtest" in the current folder and removes it at the end.
puts "cwd #{Dir.pwd}"
Dir.mkdir("rbtest") unless Dir.exist?("rbtest")
Dir.chdir("rbtest")
# text: write, append, read back
File.write("a.txt", "line1\nline2\n")
File.open("a.txt", "a") { |f| f.puts "line3"; f.print "4", "\n" }
puts File.read("a.txt")
puts File.size("a.txt")
p File.readlines("a.txt")
File.foreach("a.txt") { |l| print "> ", l }
File.open("a.txt") do |f|
  p f.gets
  p f.getc, f.getbyte
  f.seek(-2, 2)
  p f.read
  p f.eof?
  f.rewind
  p f.read(5)
end
# binary
data = ""
256.times { |i| data << i.chr }
File.binwrite("b.bin", data)
b = File.binread("b.bin")
p b.size, b.getbyte(0), b.getbyte(255)
File.open("b.bin", "r+b") { |f| f.seek(10); f.write("XYZ") }
b = File.binread("b.bin")
p b[9, 5].bytes rescue p [b.getbyte(9), b.getbyte(10), b.getbyte(11), b.getbyte(12), b.getbyte(13)]
# names
p File.exist?("a.txt"), File.file?("a.txt"), File.directory?("."), File.exist?("nope")
File.rename("a.txt", "c.txt")
p Dir.children(".").sort
Dir.mkdir("sub")
File.write("sub/d.txt", "deep")
p File.read(File.join("sub", "d.txt"))
p File.basename("x/y/z.rb"), File.basename("z.rb", ".rb"), File.dirname("x/y/z.rb"), File.extname("z.tar.gz")
p File.expand_path("sub/../c.txt")
# errors
begin
  File.read("nope")
rescue Errno::ENOENT => e
  puts "ENOENT ok"
end
begin
  Dir.mkdir("sub")
rescue Errno::EEXIST
  puts "EEXIST ok"
end
begin
  Dir.rmdir("sub")
rescue Errno::ENOTEMPTY, SystemCallError => e
  puts "rmdir refused (#{e.class})"
end
STDOUT.puts "stdout ok"
$stdout << "chain " << 1 << "\n"
p $stdin.gets
# clean up
File.delete("sub/d.txt")
Dir.rmdir("sub")
File.delete("c.txt", "b.bin")
Dir.chdir("..")
Dir.rmdir("rbtest")
p Dir.exist?("rbtest")
puts "done"
