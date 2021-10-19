# frozen_string_literal: true

Then(/^tuist builds the project$/) do
  system(@tuist, "build", "--path", @dir)
end
Then(/^tuist builds the scheme ([a-zA-Z\-]+) from the project$/) do |scheme|
  system(@tuist, "build", scheme, "--path", @dir)
end

Then(%r{^tuist builds the scheme ([a-zA-Z\-]+) \
and configuration ([a-zA-Z\-]+) from the project$}) do |scheme, configuration|
  system(@tuist, "build", scheme, "--path", @dir, "--configuration", configuration)
end

Then(%r{^tuist builds the scheme ([a-zA-Z\-]+) \
and configuration ([a-zA-Z\-]+) from the project to output path (.+)$}) do |scheme, configuration, path|
  system(@tuist, "build", scheme, "--path", @dir, "--configuration", configuration,
    "--build-output-path", File.join(@dir, path))
end

Then(/^tuist builds the project at (.+)$/) do |path|
  system(@tuist, "build", "--path", File.join(@dir, path))
end
