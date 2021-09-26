# frozen_string_literal: true

Then(/^tuist runs a task ([a-zA-Z\-]+)$/) do |name|
  system(@tuist, "exec", name, "--path", @dir)
end

Then(/^tuist runs a task (.+) with attribute (.+) as (.+)$/) do |name, attribute, attribute_value|
  system(@tuist, "exec", name, "--#{attribute}", attribute_value, "--path", @dir)
end

Then(/^content of a file named ([a-zA-Z\-_\.]+) should be equal to (.+)$/) do |file, content|
  assert_equal File.read(File.join(@dir, file)), content
end

Then(/^tuist runs ([a-zA-Z\-_]+)$/) do |command|
  system(@tuist, command, @dir)
end

Then(/^(.+) is added to PATH$/) do |executable_name|
  ENV["PATH"] = ENV["PATH"] + ":#{@dir}"
end
