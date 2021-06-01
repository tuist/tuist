# frozen_string_literal: true

Then(/^tuist runs the scheme ([a-zA-Z\-]+)t$/) do |scheme|
  system("swift", "run", "tuist", "run", "--path", @dir, scheme)
end

Then(/^tuist runs the scheme ([a-zA-Z\-]+) outputting to (.+)$/) do |scheme, file|
  system("swift", "run", "tuist", "run", "--path", @dir, scheme, ">", File.join(@dir, file))
end

Then(/^tuist runs the scheme ([a-zA-Z\-]+)$/) do |scheme|
  system("swift", "run", "tuist", "run", "--path", @dir, scheme)
end

Then(%r{^tuist runs the scheme ([a-zA-Z\-]+)\
and configuration ([a-zA-Z\-]+)$}) do |scheme, configuration|
  system("swift", "run", "tuist", "run", "--path", @dir, "--configuration", configuration, scheme)
end
