Then(/^tuist builds the project$/) do
  system("swift", "run", "tuist", "build", "--path", @dir)
end
Then(/^tuist builds the scheme ([a-zA-Z]+) from the project$/) do |scheme|
  system("swift", "run", "tuist", "build", scheme, "--path", @dir)
end

Then(/^tuist builds the scheme ([a-zA-Z]+) and configuration ([a-zA-Z]+) from the project$/) do |scheme, configuration|
  system("swift", "run", "tuist", "build", scheme, "--path", @dir, "--configuration", configuration)
end

Then(/^tuist builds the project at (.+)$/) do |path|
  system("swift", "run", "tuist", "build", "--path", File.join(@dir, path))
end
