Then(/run tuist migration list-targets for the (.+) project in ios_workspace_with_microfeature_architecture should contain:$/) do |framework, content|
    fixtures_path = File.expand_path("../../fixtures", __dir__)
    fixture_path = File.join(fixtures_path, "ios_workspace_with_microfeature_architecture/Frameworks/#{framework}Framework/#{framework}.xcodeproj/")
    assert(false, "Project #{fixture_path} not found") unless File.exist?(fixture_path)

    out, s = Open3.capture2("swift", "run", "tuist", "migration", "list-targets", "-p", fixture_path)
    assert_includes out, content
end
