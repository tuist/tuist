# frozen_string_literal: true

When(/^I initialize a (.+) application named (.+) with (.+) template$/) do |platform, name, template|
  system("swift", "run", "tuist", "init", "--template", template, "--path", @dir, "--platform", platform, "--name",
    name)
end

When(/^I initialize a (.+) application named ([^with]+)$/) do |platform, name|
  system("swift", "run", "tuist", "init", "--path", @dir, "--platform", platform, "--name", name)
end
