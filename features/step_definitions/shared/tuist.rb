# frozen_string_literal: true

Given(/tuist is available/) do
  system("swift", "build")
end

Then(/^tuist generates the project$/) do
  system("swift", "run", "tuist", "generate", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist generates the project with environment variable (.+) and value (.+)$/) do |variable, value|
  ENV[variable] = value
  system("swift", "run", "tuist", "generate", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
  ENV[variable] = nil
end

Then(/^tuist generates the project at (.+)$/) do |path|
  system("swift", "run", "tuist", "generate", "--path", File.join(@dir, path))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+)$/) do |target|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", @dir, target)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+) at (.+)$/) do |target, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), target)
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the targets ([a-zA-Z,]+) at (.+)$/) do |targets, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), *targets.split(","))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+) using xcframeworks$/) do |target|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", @dir, target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+) at (.+) using xcframeworks$/) do |target, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the targets ([a-zA-Z,]+) at (.+) using xcframeworks$/) do |targets, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), *targets.split(","), "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/tuist edits the project/) do
  system("swift", "run", "tuist", "edit", "--path", @dir, "--permanent")
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/tuist sets up the project/) do
  system("swift", "run", "tuist", "up", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/tuist generate yields error "(.+)"/) do |error|
  expected_msg = error.gsub("${ARG_PATH}", @dir)
  _, stderr, status = Open3.capture3("swift", "run", "--skip-build", "tuist", "generate", "--path", @dir)
  actual_msg = stderr.strip

  error_message = <<~EOD
    The output error message:
      #{actual_msg}

    Does not contain the expected:
      #{error}
  EOD
  assert actual_msg.include?(expected_msg), error_message
  refute status.success?
end

Then(/tuistenv should succeed in installing the latest version/) do
  constants_path = File.expand_path("../../../Sources/TuistSupport/Constants.swift", __dir__)
  # Matches: let version = "3.2.1"
  version = File.read(constants_path).match(/let\sversion\s=\s\"(.+)\"/)[1].chomp

  system("swift", "run", "tuistenv", "install", version)
end
