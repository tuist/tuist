# frozen_string_literal: true

Then(/^tuist runs a task ([a-zA-Z\-]+)$/) do |name|
    system("swift", "run", "tuist", "task", name, "--path", @dir)
end

Then(/^tuist runs a task (.+) with attribute (.+) as (.+)$/) do |name, attribute, attributeValue|
    system("swift", "run", "tuist", "task", name, "--#{attribute}", attributeValue, "--path", @dir)
end
  
Then(/^content of a file named (.+) should be equal to (.+)$/) do |file, content|
    assert_equal File.read(File.join(@dir, file)), content
end