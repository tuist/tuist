# frozen_string_literal: true

Then(/tuist scaffolds a (.+) template to (.+) named (.+) and platform (.+)/) do |template, path, name, platform|
    system("swift", "run", "tuist", "scaffold", "--list")
    system("swift", "run", "tuist", "scaffold", template, "--path", File.join(@dir, path), "--attributes", "--name", name, "--platform", platform)
end

Then(/content of a file named (.+) in a directory (.+) should be equal to (.+)/) do |file, dir, content|
    File.read(File.join(@dir, dir, file)) != content
end
