# frozen_string_literal: true

Then(/^tuist scaffolds a (.+) template in a directory (.+) named (.+) and platform (.+)$/) do |template, directory, name, platform|
    system("swift", "run", "tuist", "scaffold", template, "--path", File.join(@dir, directory), "--attributes,", "--name", name, "--platform", platform)
end
  