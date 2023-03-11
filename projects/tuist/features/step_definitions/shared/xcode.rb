# frozen_string_literal: true

require "simctl"
require "xcodeproj"

Then(/I should be able to (.+) for (iOS|macOS|tvOS|watchOS) the scheme (.+)/) do |action, platform, scheme|
  args = [
    "-scheme", scheme,
  ]
  if @workspace_path.nil?
    args.concat(["-project", @xcodeproj_path]) unless @xcodeproj_path.nil?
  else
    args.concat(["-workspace", @workspace_path]) unless @workspace_path.nil?
  end

  args << if ["iOS", "tvOS", "watchOS"].include?(platform)
    "-destination '#{Xcode.valid_simulator_destination_for_platform(platform)}'"
  else
    "-destination 'platform=OS X,arch=x86_64'"
  end

  args.concat(["-derivedDataPath", @derived_data_path])

  args << "clean"
  args << action
  args << "CODE_SIGNING_ALLOWED=NO"
  args << "CODE_SIGNING_IDENTITY=\"\""
  args << "CODE_SIGNING_REQUIRED=NO"
  args << "CODE_SIGN_ENTITLEMENTS=\"\""

  xcodebuild(*args)
end

Then(/I should be able to (.+) for device of (iOS|macOS|tvOS|watchOS) the scheme (.+)/) do |action, platform, scheme|
  args = [
    "-scheme", scheme,
  ]
  if @workspace_path.nil?
    args.concat(["-project", @xcodeproj_path]) unless @xcodeproj_path.nil?
  else
    args.concat(["-workspace", @workspace_path]) unless @workspace_path.nil?
  end

  args << if ["iOS", "tvOS", "watchOS"].include?(platform)
    "-destination generic/platform=#{platform}"
  else
    "-destination generic/platform=OS X"
  end

  args.concat(["-derivedDataPath", @derived_data_path])

  args << "clean"
  args << action
  args << "CODE_SIGNING_ALLOWED=NO"
  args << "CODE_SIGNING_IDENTITY=\"\""
  args << "CODE_SIGNING_REQUIRED=NO"
  args << "CODE_SIGN_ENTITLEMENTS=\"\""

  xcodebuild(*args)
end

Then(/the scheme (.+) has a build setting (.+) with value (.+) for the configuration (.+)/) do |scheme, key, value, config| # rubocop:disable Metrics/LineLength
  args = [
    "-scheme", scheme,
    "-workspace", @workspace_path,
    "-configuration", config,
    "-showBuildSettings",
  ]

  out, err, status = Open3.capture3("xcodebuild", *args)
  flunk(err) unless status.success?

  search_for = "#{key} = #{value}"
  assert(out.include?(search_for), "Couldn't find '#{search_for}'")
end

Then(/^the target (.+) should have the build phase (.+)$/) do |target_name, phase_name|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.detect { |b| b.display_name == phase_name }
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(/^in project (.+) the target (.+) should have the build phase (.+) with a dependency file named (.+)$/)  do |project_name, target_name, phase_name, dependency_file_name|
  workspace = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  project_file_reference = workspace.file_references.detect { |f| File.basename(f.path, ".xcodeproj") == project_name }
  project = Xcodeproj::Project.open(File.join(@dir, project_file_reference.path))
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.detect { |b| b.display_name == phase_name }
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  dependency_file = build_phase.dependency_file
  flunk("The build phase  #{phase_name} doesn't have a dependency file") if dependency_file.nil?
  assert_equal dependency_file_name, dependency_file 
end

Then(/^the target (.+) should have the build phase (.+) in the first position$/) do |target_name, phase_name|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.first
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(%r{^in project (.+) the target (.+) should \
have the build phase (.+) in the first position$}) do |project_name, target_name, phase_name|
  workspace = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  project_file_reference = workspace.file_references.detect { |f| File.basename(f.path, ".xcodeproj") == project_name }
  flunk("Project #{project_name} not found in the workspace") if project_file_reference.nil?
  project = Xcodeproj::Project.open(File.join(@dir, project_file_reference.path))
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.first
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(/^the target (.+) should have the build phase (.+) in the last position$/) do |target_name, phase_name|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.last
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(%r{^in project (.+) the target (.+) should \
have the build phase (.+) in the last position$}) do |project_name, target_name, phase_name|
  workspace = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  project_file_reference = workspace.file_references.detect { |f| File.basename(f.path, ".xcodeproj") == project_name }
  flunk("Project #{project_name} not found in the workspace") if project_file_reference.nil?
  project = Xcodeproj::Project.open(File.join(@dir, project_file_reference.path))
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.last
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert_equal phase_name, build_phase.name
end

Then(%r{^in project (.+) in the target (.+) the build phase in the first position should \
have (.+) as an output path$}) do |project_name, target_name, output_path_name|
  workspace = Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path)
  project_file_reference = workspace.file_references.detect { |f| File.basename(f.path, ".xcodeproj") == project_name }
  flunk("Project #{project_name} not found in the workspace") if project_file_reference.nil?
  project = Xcodeproj::Project.open(File.join(@dir, project_file_reference.path))
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_phase = target.build_phases.first
  flunk("The target #{target_name} doesn't have build phases") if build_phase.nil?
  assert build_phase.output_paths.include? output_path_name
end

Then(/the target (.+) should have the build rule (.+) with pattern (.+)$/) do |target_name, build_rule_name, pattern|
  project = Xcodeproj::Project.open(@xcodeproj_path)
  targets = project.targets
  target = targets.detect { |t| t.name == target_name }
  flunk("Target #{target_name} not found in the project") if target.nil?
  build_rule = target.build_rules.detect { |b| b.name == build_rule_name }
  flunk("The target #{target_name} doesn't have build rules") if build_rule.nil?
  assert_equal build_rule_name, build_rule.name
  assert_equal pattern, build_rule.file_patterns
end
