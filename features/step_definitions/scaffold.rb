# frozen_string_literal: true

Then(/tuist scaffolds a (.+) template to (.+) named (.+)/) do |template, path, name|
    system("swift", "run", "tuist", "scaffold", template, "--path", File.join(@dir, path), "--name", name)
end

Then(/content of a file named (.+) in a directory (.+) should be equal to (.+)/) do |file, dir, content|
    assert_equal File.read(File.join(@dir, dir, file)), content
end

Then(/content of a file named (.+) in a directory (.+) should be equal to:$/) do |file, dir, content|
    assert_equal File.read(File.join(@dir, dir, file)), content
end
