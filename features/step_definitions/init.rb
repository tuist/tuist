# frozen_string_literal: true

When(/I initialize a (.+) (.+) named (.+)/) do |platform, product, name|
  system("swift", "run", "tuist", "init", "--path", @dir, "--platform", platform, "--product", product, "--name", name)
end

Then(/I should have a file named (.+)/) do |file_name|
  file = Dir.glob(File.join(@dir, "**/#{file_name}**")).first
  assert(false, "File `#{file_name}` not found") unless File.exist?(file)
end
