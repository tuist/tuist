# frozen_string_literal: true

Given(/tuist is available/) do
  system("swift", "build")
end

Then(/tuist generates the project/) do
  system("swift", "run", "tuist", "generate", "--path", @dir)
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

Then(/tuistenv should succeed in installing "(.+)"/) do |ref|
  system("swift", "run", "tuistenv", "install", ref)
end
