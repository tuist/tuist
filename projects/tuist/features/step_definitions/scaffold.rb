# frozen_string_literal: true

Then(/tuist scaffolds a (.+) template named (.+)/) do |template, name|
  system(@tuist, "scaffold", template, "--path", @dir, "--name", name)
end

Then(/content of a file named (.+) in a directory (.+) should be equal to (.+)/) do |file, dir, content|
  assert_equal File.read(File.join(@dir, dir, file)), content
end

Then(/content of a file named (.+) in a directory (.+) should be equal to:$/) do |file, dir, content|
  assert_equal File.read(File.join(@dir, dir, file)), content
end
