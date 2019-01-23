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

Then(/tuist generates reports error "(.+)"/) do |error|
  expected_msg = error.sub!("${ARG_PATH}", @dir)
  stdin, stdout, stderr, wait_thr = Open3.popen3("swift", "run", "tuist", "generate", "--path", @dir) 
  actual_msg = stderr.gets.to_s.strip
  assert_equal(expected_msg, actual_msg)
  assert_equal(wait_thr.value.exitstatus, 1)
end
