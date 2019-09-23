# frozen_string_literal: true

require 'simctl'
require 'xcodeproj'

Then(/I should be able to (.+) the scheme (.+)/) do |action, scheme|
  @derived_data_path = File.join(@dir, "DerivedData")

  args = [
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "-derivedDataPath", @derived_data_path,
    "clean", action
  ]

  if action == "test"
    device = SimCtl.device(name: "iPhone 11", is_available: true)
    args << "-destination 'id=#{device.udid}'" unless device.nil?
  end

  args << "CODE_SIGNING_ALLOWED=NO"
  args << "CODE_SIGNING_IDENTITY=\"iPhone Developer\""

  xcodebuild(*args)
end

Then(/the scheme (.+) has a build setting (.+) with value (.+) for the configuration (.+)/) do |scheme, key, value, config| # rubocop:disable Metrics/LineLength
  args = [
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "-configuration", config,
    "-showBuildSettings"
  ]

  out, err, status = Open3.capture3("xcodebuild", *args)
  flunk(err) unless status.success?

  search_for = "#{key} = #{value}"
  assert(out.include?(search_for), "Couldn't find '#{search_for}'")
end

Then(/the target (.+) should have the build phase (.+) in the first position/) do |target_name, phase_name|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.first
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(/the target (.+) should have the build phase (.+) in the last position/) do |target_name, phase_name|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.last
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end
