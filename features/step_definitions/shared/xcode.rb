# frozen_string_literal: true

require 'simctl'

Then(/I should be able to (.+) the scheme (.+)/) do |action, scheme|
  @derived_data_path = File.join(@dir, "DerivedData")

  args = [
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "-derivedDataPath", @derived_data_path,
    "clean", action
  ]

  if action == "test"
    device = SimCtl.device(name: "iPhone 7", availability: "(available)")
    args << "-destination 'id=#{device.udid}'" unless device.nil?
  end

  args << "CODE_SIGNING_ALLOWED=NO"
  args << "CODE_SIGNING_IDENTITY=\"iPhone Developer\""

  xcodebuild(*args)
end

Then(/the scheme (.+) has a build setting (.+) with value (.+) for the configuration (.+)/) do |scheme, key, value, config|
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
