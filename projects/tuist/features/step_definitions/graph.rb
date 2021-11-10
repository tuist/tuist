# frozen_string_literal: true

Then(/^tuist graph$/) do
  system(@tuist, "graph", "--path", @dir, "--output-path", @dir)
end

Then(/^tuist graph of ([a-zA-Z]+)$/) do |target_name|
  system(@tuist, "graph", "--path", @dir, "--output-path", @dir, target_name)
end

Then(/^I should be able to open a graph file$/) do
  binary_path = File.join(@dir, "graph.png")
  system("file", binary_path)
end
