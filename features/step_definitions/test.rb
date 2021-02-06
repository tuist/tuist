require 'xcodeproj'

Then(/^tuist tests the project$/) do
    system("swift", "run", "tuist", "test", "--path", @dir)
  end
Then(/^tuist tests the scheme ([a-zA-Z\-]+) from the project$/) do |scheme|
  system("swift", "run", "tuist", "test", scheme, "--path", @dir)
end

Then(/^tuist tests the scheme ([a-zA-Z\-]+) and configuration ([a-zA-Z]+) from the project$/) do |scheme, configuration|
  system("swift", "run", "tuist", "test", scheme, "--path", @dir, "--configuration", configuration)
end

Then(/^tuist tests the project at (.+)$/) do |path|
  system("swift", "run", "tuist", "test", "--path", File.join(@dir, path))
end

Then(/^tuist tests the project with automation path at (.+)$/) do |path|
  system("swift", "run", "tuist", "test", "--path", @dir, "--automation-path", File.join(@dir, path))
  @workspace_path = Dir.glob(File.join(@dir, path, "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, path, "*.xcodeproj")).first
end

Then(/^generated project is deleted/) do
  FileUtils.rm_rf(@workspace_path)
  FileUtils.rm_rf(@xcodeproj_path)
end

Then(/^project does not contain ([a-zA-Z\-]+) scheme/) do |scheme_name|
  scheme = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  .schemes
  .keys
  .detect { |scheme| scheme == scheme_name }
  flunk("Project contains #{scheme_name} scheme") if !scheme.nil?
end

Then(/^project contains ([a-zA-Z\-]+) scheme/) do |scheme_name|
  scheme = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  .schemes
  .keys
  .detect { |scheme| scheme == scheme_name }
  flunk("Project does not contain #{scheme_name} scheme") if scheme.nil?
end
