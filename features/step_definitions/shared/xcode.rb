Then(/I should be able to (.+) the scheme (.+)/) do |action, scheme|
  Tuist::System.xcodebuild(
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "clean", action
  )
end
