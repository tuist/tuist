# frozen_string_literal: true

require "open3"
Given(/tuist is available/) do
  project_root = File.expand_path("../../../../..", __dir__)
  # On CI we expect tuist to be built already by the previous job `release_build`, so we skip `swift build`

  if ENV["CI"].nil?
    ["tuist", "ProjectDescription", "tuistenv"].each do |product|
      system(
        "swift",
        "build",
        "-c",
        "release",
        "--product",
        product,
        "--package-path",
        project_root
      )
    end
  end

  # `tuist` release build expect to have `vendor` and `Templates` in the same directory where the executable is
  FileUtils.cp_r(File.join(project_root, "projects/tuist/vendor"), File.join(project_root, ".build/release/vendor"))
  FileUtils.cp_r(File.join(project_root, "Templates"), File.join(project_root, ".build/release/Templates"))
  @tuist = File.join(project_root, ".build/release/tuist")
  @tuistenv = File.join(project_root, ".build/release/tuistenv")
end

Then(/^tuist generates the project$/) do
  system(@tuist, "generate", "--no-cache", "--no-open", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist generates the project and outputs: (.+)$/) do |output|
  out, err, status = Open3.capture3(@tuist, "generate", "--no-cache", "--no-open", "--path", @dir)
  assert(status.success?, err)
  assert out.include?(output), "The output from Tuist generate doesn't include: #{output}"
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/^tuist generates the project with environment variable (.+) and value (.+)$/) do |variable, value|
  ENV[variable] = value
  system(@tuist, "generate", "--no-cache", "--no-open", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
  ENV[variable] = nil
end

Then(%r{^tuist generates the project at ([a-zA-Z/]+)$}) do |path|
  system(@tuist, "generate", "--no-cache", "--no-open", "--path", File.join(@dir, path))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

When(/^tuist focuses the target ([a-zA-Z\-]+)$/) do |target|
  system(@tuist, "generate", "--no-open", "--path", @dir, target)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(/^tuist focuses the targets ([a-zA-Z,\-]+)$/) do |targets|
  system(@tuist, "generate", "--no-open", "--path", @dir, *targets.split(","))
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(/^tuist focuses the target ([a-zA-Z]+) with ([a-zA-Z]+) profile$/) do |target, cache_profile|
  system(@tuist, "generate", "--no-open", "--path", @dir, target, "--profile", cache_profile)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(%r{^tuist focuses the target ([a-zA-Z\-]+) at ([a-zA-Z/]+)$}) do |target, path|
  system(@tuist, "generate", "--no-open", "--path", File.join(@dir, path), target)
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

When(%r{^tuist focuses the targets ([a-zA-Z,\-]+) at ([a-zA-Z/]+)$}) do |targets, path|
  system(@tuist, "generate", "--no-open", "--path", File.join(@dir, path), *targets.split(","))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

When(/^tuist focuses the target ([a-zA-Z\-]+) using xcframeworks$/) do |target|
  system(@tuist, "generate", "--no-open", "--path", @dir, target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(/^tuist focuses the targets ([a-zA-Z,\-]+) using xcframeworks$/) do |targets|
  system(@tuist, "generate", "--no-open", "--path", @dir, *targets.split(","),
    "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(/^tuist focuses the targets ([a-zA-Z,\-]+) using (device|simulator) xcframeworks$/) do |targets, type|
  system(@tuist, "generate", "--no-open", "--path", @dir, *targets.split(","),
    "--xcframeworks", "--destination #{type}")
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

When(%r{^tuist focuses the target ([a-zA-Z\-]+) at ([a-zA-Z/]+) using xcframeworks$}) do |target, path|
  system(@tuist, "generate", "--no-open", "--path", File.join(@dir, path), target, "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

When(%r{^tuist focuses the targets ([a-zA-Z,\-]+) at ([a-zA-Z/]+) using xcframeworks$}) do |targets, path|
  system(@tuist, "generate", "--no-open", "--path", File.join(@dir, path), *targets.split(","),
    "--xcframeworks")
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/tuist edits the project/) do
  system(@tuist, "edit", "--path", @dir, "--permanent")
  @workspace_path = Dir.glob(File.join(@dir, "Manifests.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "Manifests.xcodeproj")).first
end

Then(/tuist sets up the project/) do
  system(@tuist, "up", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "*.xcodeproj")).first
end

Then(/tuist generate yields error "(.+)"/) do |error|
  xcode_version, _, _ = Open3.capture3("xcodebuild -version | sed -n \"s/Xcode //p\"")
  versioned_msg = error.gsub("${XCODE_VERSION}", xcode_version.chomp())
  expected_msg = versioned_msg.gsub("${ARG_PATH}", @dir)
  _, stderr, status = Open3.capture3(@tuist, "generate", "--no-cache", "--no-open", "--path", @dir)
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

  system(@tuistenv, "install", version)
end
