require 'simctl'

Then(/I should be able to (.+) the scheme (.+)/) do |action, scheme|
  args = [
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "clean", action
  ]

  if action == "test"
    device = SimCtl.device({name: "iPhone 7", availability: "(available)"})
    args << "-destination 'id=#{device.udid}'" unless device.nil?
  end

  args << "CODE_SIGN_IDENTITY="
  args << "CODE_SIGNING_REQUIRED=NO"
  xcodebuild(*args)
end
