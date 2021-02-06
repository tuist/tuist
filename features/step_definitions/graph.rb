Then(/^tuist graph$/) do
  system("swift", "run", "tuist", "graph", "--path", @dir, "--output-path", @dir)
end

Then(/^tuist graph of ([a-zA-Z]+)$/) do |target_name|
  system("swift", "run", "tuist", "graph", "--path", @dir, "--output-path", @dir, target_name)
end

Then(/^I should be able to open a graph file$/) do
  binary_path = File.join(@dir, "graph.png")
  out, err, status = Open3.capture3("file", binary_path)
  assert(status.success?, err)
end
