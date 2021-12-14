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

Then(/^current directory is added to PATH$/) do
  ENV["PATH"] = ENV["PATH"] + ":/#{@dir}"
end
