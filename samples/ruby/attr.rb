# File attributes and times on sgnano (2026-10-16): read-only / hidden / system / archive, and the clock.
# Read-only files cannot be written, deleted or renamed (Errno::EACCES). Works in the folder "att" and removes it at the end.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue Exception => e
  puts "#{name}: raised #{e.class}"
end

Dir.mkdir("att") unless File.directory?("att")
Dir.chdir("att")
File.write("f.txt", "abc")
t("new file") { s = File.stat("f.txt"); [s.archive?, s.hidden?, s.system?, s.readonly?, format("%02x", s.attributes)] }
t("hide") do
  File.set_attributes("f.txt", File::ATTR_HIDDEN | File::ATTR_SYSTEM | File::ATTR_ARCHIVE)
  s = File.stat("f.txt")
  [s.hidden?, s.system?, s.archive?, s.readonly?]
end
t("read-only") { File.set_attributes("f.txt", File::ATTR_READONLY); File.attributes("f.txt") }
t("writable?") { [File.writable?("f.txt"), File.stat("f.txt").writable?, File.stat("f.txt").mode & 0222] }
t("write") { File.write("f.txt", "x") }
t("append") { File.open("f.txt", "a") { |f| f.write("x") } }
t("delete") { File.delete("f.txt") }
t("rename") { File.rename("f.txt", "g.txt") }
t("read") { File.read("f.txt") }
t("chmod") { File.chmod(0644, "f.txt"); [File.writable?("f.txt"), File.attributes("f.txt")] }
t("folder") do
  Dir.mkdir("d")
  File.set_attributes("d", File::ATTR_HIDDEN)
  [File.stat("d").hidden?, File.directory?("d"), format("%02x", File.attributes("d"))]
end
t("missing") { File.set_attributes("nothing.txt", 0) }
t("constants") { [File::ATTR_READONLY, File::ATTR_HIDDEN, File::ATTR_SYSTEM, File::ATTR_DIRECTORY, File::ATTR_ARCHIVE] }
t("clock") { [Time.now.to_s, Time.now.to_i, Machine.clock_set?] }
t("inspect") { [Time.at(1792112524).inspect, Time.at(1792112524.25).inspect, Time.at(0).to_s] }
t("stat inspect") { File.stat("f.txt").inspect[0, 40] }
File.delete("f.txt")
File.set_attributes("d", 0)
Dir.rmdir("d")
Dir.chdir("..")
Dir.rmdir("att")
t("cleaned") { File.exist?("att") }
puts "done"
