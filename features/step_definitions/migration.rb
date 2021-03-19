# frozen_string_literal: true
Then(/run tuist migration list-targets for (.+) in ios_workspace_with_microfeature_architecture matches (.+)$/) do |framework, json_file|
  fixtures_path = File.expand_path("../../fixtures", __dir__)
  fixture_path = File.join(fixtures_path,
    "ios_workspace_with_microfeature_architecture/Frameworks/#{framework}Framework/#{framework}.xcodeproj/")
  resources_path = File.expand_path("../resources", __dir__)
  expected_json = File.read("#{resources_path}/#{json_file}")

  assert(false, "Project #{fixture_path} not found") unless File.exist?(fixture_path)

  out, s = Open3.capture2("swift", "run", "tuist", "migration", "list-targets", "-p", fixture_path)

  assert(out.include?(expected_json))
end
