# frozen_string_literal: true

Then(/^content of a file named ([a-zA-Z\-_\.]+) should be equal to (.+)$/) do |file, content|
  assert_equal File.read(file), content
end

Then(/^tuist runs ([a-zA-Z\-_]+) with the current directory$/) do |command|
  system(@tuist, command, @dir)
end

Then(/^tuist runs ([a-zA-Z\-_]+)$/) do |command|
  system(@tuist, command, "--path", @dir)
end

Then(/^tuist fails running ([a-zA-Z\-_]+)$/) do |command|
    _, _, status = Open3.capture3(@tuist, command, "--path", @dir)
    assert(!status.success?, "Running #{command} must be failed")
end

Then(/^current directory is added to PATH$/) do
  ENV["PATH"] = ENV["PATH"] + ":/#{@dir}"
end

Then(/^environment variable ([a-zA-Z\-_\.]+) is not defined$/) do |key|
  ENV.delete(key)
end

Then(/^environment variable ([a-zA-Z\-_\.]+) is defined as (.+)$/) do |key, value|
  ENV[key] = value
end
