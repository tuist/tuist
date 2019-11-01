# frozen_string_literal: true

When(/I initialize a (.+) application named (.+)/) do |platform, name|
  system("swift", "run", "tuist", "init", "--path", @dir, "--platform", platform, "--name", name)
end
