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

  args << "CODE_SIGN_IDENTITY="
  args << "CODE_SIGNING_REQUIRED=NO"
  xcodebuild(*args)
end
