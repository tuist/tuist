# frozen_string_literal: true

require "xcodeproj"


Then(/^tuist tests the scheme ([a-zA-Z\-]+) from the project$/) do |scheme|
  system(@tuist, "test", scheme, "--path", @dir)
end

Then(/^tuist tests the scheme ([a-zA-Z\-]+) and configuration ([a-zA-Z]+) from the project$/) do |scheme, configuration|
  system(@tuist, "test", scheme, "--path", @dir, "--configuration", configuration)
end

Then(/^tuist tests the project at (.+)$/) do |path|
  system(@tuist, "test", "--path", File.join(@dir, path))
end

Then(/^tuist tests the project$/) do
  system(@tuist, "test", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "Automation", "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "Automation", "*.xcodeproj")).first
end

Then(/^tuist tests and cleans the project$/) do
  system(@tuist, "test", "--clean", "--path", @dir)
  @workspace_path = Dir.glob(File.join(@dir, "Automation", "*.xcworkspace")).first
  @xcodeproj_path = Dir.glob(File.join(@dir, "Automation", "*.xcodeproj")).first
end

Then(/^generated project is deleted/) do
  FileUtils.rm_rf(@workspace_path)
  FileUtils.rm_rf(@xcodeproj_path)
end

Then(/^([a-zA-Z\-]+) scheme has nothing to test/) do |scheme_name|
  scheme_file = File.join(Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path).schemes[scheme_name],
    "xcshareddata", "xcschemes", "#{scheme_name}.xcscheme")
  scheme = Xcodeproj::XCScheme.new(scheme_file)
  flunk("Project #{scheme_name} scheme has nothing to test") unless scheme.test_action.testables.empty?
end

Then(/^([a-zA-Z\-]+) scheme has something to test/) do |scheme_name|
  scheme_file = File.join(Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path).schemes[scheme_name],
    "xcshareddata", "xcschemes", "#{scheme_name}.xcscheme")
  scheme = Xcodeproj::XCScheme.new(scheme_file)
  flunk("Project #{scheme_name} scheme has nothing to test") if scheme.test_action.testables.empty?
end
