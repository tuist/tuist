# frozen_string_literal: true

Then("tuist generates the documentation for {string}") do |target|
  system("swift", "run", "tuist", "doc", "--path", @dir + "/" + target, target, "--files-only")
end
