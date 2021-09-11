# frozen_string_literal: true

Then(/^tuist runs the scheme ([a-zA-Z\-]+)t$/) do |scheme|
  system(@tuist, "run", "--path", @dir, scheme)
end

Then(/^tuist runs the scheme ([a-zA-Z\-]+) outputting to (.+)$/) do |scheme, file|
  system(@tuist, "run", "--path", @dir, scheme, ">", File.join(@dir, file))
end

Then(/^tuist runs the scheme ([a-zA-Z\-]+)$/) do |scheme|
  system(@tuist, "run", "--path", @dir, scheme)
end

Then(%r{^tuist runs the scheme ([a-zA-Z\-]+)\
and configuration ([a-zA-Z\-]+)$}) do |scheme, configuration|
  system(@tuist, "run", "--path", @dir, "--configuration", configuration, scheme)
end
