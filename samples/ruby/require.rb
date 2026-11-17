# require / require_relative の見本（2026-11-02）。require_lib.rb と同じフォルダに置いて走らせる
require_relative "require_lib"
raise "require_relative did not define req_hello" unless req_hello == "hello from lib"
raise "require_relative loaded twice" unless require_relative("require_lib") == false
puts "require: all ok"
