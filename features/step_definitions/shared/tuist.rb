# frozen_string_literal: true

Given(/tuist is available/) do
  system("swift", "build")
end

Then(/tuist generates the project/) do
  system("swift", "run", "tuist", "generate", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
end

Then(/tuist sets up the project/) do
  system("swift", "run", "tuist", "up", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
end
