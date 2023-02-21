# frozen_string_literal: true
require "xcodeproj"

Then(/^tuist builds the project$/) do
  system(@tuist, "build", "--path", @dir)
end

Then(/^tuist builds the scheme ([a-zA-Z\-]+) from the project$/) do |scheme|
  system(@tuist, "build", scheme, "--path", @dir)
end

Then(%r{^tuist builds the scheme ([a-zA-Z\-_]+) from the project at ([a-zA-Z/]+)$}) do |scheme, path|
  system(@tuist, "build", scheme, "--path", File.join(@dir, path))
end

Then(%r{^tuist builds the scheme ([a-zA-Z\-_]+) \
and configuration ([a-zA-Z\-]+) from the project$}) do |scheme, configuration|
  system(@tuist, "build", scheme, "--path", @dir, "--configuration", configuration)
end

Then(%r{^tuist builds the scheme ([a-zA-Z\-_]+) \
and configuration ([a-zA-Z\-]+) from the project to output path (.+)$}) do |scheme, configuration, path|
  system(@tuist, "build", scheme, "--path", @dir, "--configuration", configuration,
    "--build-output-path", File.join(@dir, path))
end

Then(/^tuist builds the project at (.+)$/) do |path|
  system(@tuist, "build", "--path", File.join(@dir, path))
end

Then(/^xcodebuild compiles the docc archive$/) do
  args = [
    "docbuild"      
  ]
  args.concat(["-project", @xcodeproj_path]) unless @xcodeproj_path.nil?
  xcodebuild(*args)
end
