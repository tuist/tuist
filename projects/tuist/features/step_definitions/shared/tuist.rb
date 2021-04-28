# frozen_string_literal: true
require "open3"

Given(/tuist is available/) do
  system("swift", "build", "--package-path", File.expand_path("../../../../..", __dir__))
end

Then(/^tuist generates the project$/) do
  system("swift", "run", "tuist", "generate", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist generates the project and outputs: (.+)$/) do |output|
  out, err, status = Open3.capture3("swift", "run", "tuist", "generate", "--path", @dir)
  assert(status.success?, err)
  assert out.include?(output), "The output from Tuist generate doesn't include: #{output}"
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

Then(%r{^tuist generates the project at ([a-zA-Z]/+)$}) do |path|
  system("swift", "run", "tuist", "generate", "--path", File.join(@dir, path))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+)$/) do |target|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", @dir, target)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+) with ([a-zA-Z]+) profile$/) do |target, cache_profile|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", @dir, target, "--profile", cache_profile)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(%r{^tuist focuses the target ([a-zA-Z]+) at ([a-zA-Z]/+)$}) do |target, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), target)
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(%r{^tuist focuses the targets ([a-zA-Z,]+) at ([a-zA-Z]/+)$}) do |targets, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), *targets.split(","))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^tuist focuses the target ([a-zA-Z]+) using xcframeworks$/) do |target|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", @dir, target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(%r{^tuist focuses the target ([a-zA-Z]+) at ([a-zA-Z]/+) using xcframeworks$}) do |target, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(%r{^tuist focuses the targets ([a-zA-Z,]+) at ([a-zA-Z]/+) using xcframeworks$}) do |targets, path|
  system("swift", "run", "tuist", "focus", "--no-open", "--path", File.join(@dir, path), *targets.split(","),
    "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/tuist edits the project/) do
  system("swift", "run", "tuist", "edit", "--path", @dir, "--permanent")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
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
  constants_path = File.expand_path("../../../../../Sources/TuistSupport/Constants.swift", __dir__)
  # Matches: let version = "3.2.1"
  version = File.read(constants_path).match(/let\sversion\s=\s\"(.+)\"/)[1].chomp

  system("swift", "run", "tuistenv", "install", version)
end
