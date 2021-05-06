# frozen_string_literal: true
require "xcodeproj"

Then(/^tuist warms the cache$/) do
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir)
end

Then(/^tuist warms the cache of ([a-zA-Z]+)$/) do |target_name|
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir, target_name)
end

Then(/^tuist warms the cache with xcframeworks$/) do
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir, "--xcframeworks")
end

Then(/^tuist warms the cache with ([a-zA-Z]+) profile$/) do |cache_profile|
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir, "--profile", cache_profile)
end

Then(/^([a-zA-Z]+) links the framework ([a-zA-Z]+) from the cache/) do |target_name, framework_name|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} doesn't exist in any of the projects' targets of the workspace") if target.nil?
  build_file = target.frameworks_build_phases.files.filter do |f|
    f.display_name.include?("#{framework_name}.framework")
  end .first
  unless build_file
    flunk("Target #{target_name} doesn't link the framework #{framework}")
  end
  framework_path = File.expand_path(build_file.file_ref.full_path.to_s, @dir)
  unless framework_path.include?(@cache_dir)
    flunk(
      "The framework '#{framework_name}' linked from target '#{target_name}' \
      has a path outside the cache: #{framework_path}"
    )
  end
end

Then(/^([a-zA-Z]+) links the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} doesn't exist in any of the projects' targets of the workspace") if target.nil?
  xcframework_deps = target.frameworks_build_phases.file_display_names.filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.include?("#{xcframework}.xcframework")
    flunk(
      "Target #{target_name} doesn't link the xcframework #{xcframework}. \
      It links the xcframeworks: #{xcframework_deps.join(", ")}"
    )
  end
end

Then(/^([a-zA-Z]+) links the framework ([a-zA-Z]+)$/) do |target_name, framework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} doesn't exist in any of the projects' targets of the workspace") if target.nil?
  framework_deps = target.frameworks_build_phases.file_display_names.filter { |d| d.include?(".framework") }
  unless framework_deps.include?("#{framework}.framework")
    flunk("Target #{target_name} doesn't link the framework #{framework}. \
    It links the frameworks: #{framework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) embeds the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map(&:file_display_names)
    .filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.include?("#{xcframework}.xcframework")
    flunk("Target #{target_name} doesn't embed the xcframework #{xcframework}. \
    It embeds the xcframeworks: #{xcframework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) embeds the framework ([a-zA-Z]+)$/) do |target_name, framework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  framework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map(&:file_display_names)
    .filter { |d| d.include?(".framework") }
  unless framework_deps.include?("#{framework}.framework")
    flunk("Target #{target_name} doesn't embed the framework #{framework}. \
    It embeds the frameworks: #{framework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) doesn't embed the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map(&:file_display_names)
    .filter { |d| d.include?(".xcframework") }
  if xcframework_deps.include?("#{xcframework}.xcframework")
    flunk("Target #{target_name} embeds the xcframework #{xcframework}.")
  end
end

Then(/^([a-zA-Z]+) does not embed any xcframeworks$/) do |target_name|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map(&:targets).detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map(&:file_display_names)
    .filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.empty?
    flunk("Target #{target_name} should not embed any xcframeworks, \
    although it does embed the following xcframeworks: #{xcframework_deps.join(", ")}")
  end
end
