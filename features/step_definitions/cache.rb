require 'xcodeproj'

Then(/^tuist warms the cache$/) do
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir)
end

Then(/^tuist warms the cache with xcframeworks$/) do
  system("swift", "run", "tuist", "cache", "warm", "--path", @dir, "--xcframeworks")
end

Then(/^([a-zA-Z]+) links the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} doesn't exist in any of the projects' targets of the workspace") if target.nil?
  xcframework_deps = target.frameworks_build_phases.file_display_names.filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.include?("#{xcframework}.xcframework")
    flunk("Target #{target_name} doesn't link the xcframework #{xcframework}. It links the xcframeworks: #{xcframework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) links the framework ([a-zA-Z]+)$/) do |target_name, framework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} doesn't exist in any of the projects' targets of the workspace") if target.nil?
  framework_deps = target.frameworks_build_phases.file_display_names.filter { |d| d.include?(".framework") }
  unless framework_deps.include?("#{framework}.framework")
    flunk("Target #{target_name} doesn't link the framework #{framework}. It links the frameworks: #{framework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) embeds the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map { |b| b.file_display_names }
    .filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.include?("#{xcframework}.xcframework")
    flunk("Target #{target_name} doesn't embed the xcframework #{xcframework}. It embeds the xcframeworks: #{xcframework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) embeds the framework ([a-zA-Z]+)$/) do |target_name, framework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  framework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map { |b| b.file_display_names }
    .filter { |d| d.include?(".framework") }
  unless framework_deps.include?("#{framework}.framework")
    flunk("Target #{target_name} doesn't embed the framework #{framework}. It embeds the frameworks: #{framework_deps.join(", ")}")
  end
end

Then(/^([a-zA-Z]+) doesn't embed the xcframework ([a-zA-Z]+)$/) do |target_name, xcframework|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map { |b| b.file_display_names }
    .filter { |d| d.include?(".xcframework") }
  if xcframework_deps.include?("#{xcframework}.xcframework")
    flunk("Target #{target_name} embeds the xcframework #{xcframework}.")
  end
end

Then(/^([a-zA-Z]+) does not embed any xcframeworks$/) do |target_name|
  projects = Xcode.projects(@workspace_path)
  target = projects.flat_map { |p| p.targets }.detect { |t| t.name == target_name }
  flunk("Target #{target_name} in any of the projects of the workspace") if target.nil?
  xcframework_deps = target
    .copy_files_build_phases
    .filter { |b| b.symbol_dst_subfolder_spec == :frameworks }
    .flat_map { |b| b.file_display_names }
    .filter { |d| d.include?(".xcframework") }
  unless xcframework_deps.empty?
    flunk("Target #{target_name} should not embed any xcframeworks, although it does embed the following xcframeworks: #{xcframework_deps.join(", ")}")
  end
end
