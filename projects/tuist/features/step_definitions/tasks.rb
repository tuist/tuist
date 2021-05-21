# frozen_string_literal: true

Then(/^tuist runs a task ([a-zA-Z\-]+)$/) do |name|
  system("swift", "run", "tuist", "exec", name, "--path", @dir)
end

Then(/^tuist runs a task (.+) with attribute (.+) as (.+)$/) do |name, attribute, attribute_value|
  system("swift", "run", "tuist", "exec", name, "--#{attribute}", attribute_value, "--path", @dir)
end

Then(/^content of a file named ([a-zA-Z\-_]+) should be equal to (.+)$/) do |file, content|
  assert_equal File.read(File.join(@dir, file)), content
end
