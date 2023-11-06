# frozen_string_literal: true

When(/^I initialize a (.+) application named (.+) with (.+) template$/) do |platform, name, template|
  system(@tuist, "init", "--template", template, "--path", @dir, "--platform", platform, "--name",
    name)
end

When(/^I initialize a (.+) application named ([a-zA-Z\-_]+)$/) do |platform, name|
  system(@tuist, "init", "--path", @dir, "--platform", platform, "--name", name)
end

When(/^I initialize a project from the template (.+)$/) do |template_url|
  system(@tuist, "init", "--path", @dir, "-t", template_url)
end
