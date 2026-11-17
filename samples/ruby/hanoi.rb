# Tower of Hanoi
$moves = 0
def hanoi(n, from, to, via, show)
  return if n == 0
  hanoi(n - 1, from, via, to, show)
  $moves += 1
  puts "disk #{n}: #{from} -> #{to}" if show
  hanoi(n - 1, via, to, from, show)
end
hanoi(4, "A", "C", "B", true)
puts "4 disks: #{$moves} moves"
$moves = 0
hanoi(12, "A", "C", "B", false)
puts "12 disks: #{$moves} moves"
