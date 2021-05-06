# frozen_string_literal: true
Then(/tuist lints project's code and passes/) do
  _, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  flunk(err) unless status.success?
end

Then(/tuist lints project's code and fails/) do
  _, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", "--path", @dir)
  flunk(err) if status.success?
end

Then(/tuist lints code of target with name "(.+)" and passes/) do |target_name|
  _, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", target_name, "--path", @dir)
  flunk(err) unless status.success?
end

Then(/tuist strict lints code of target with name "(.+)" and fails/) do |target_name|
  _, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", target_name, "--path", @dir, "--strict")
  flunk(err) if status.success?
end

Then(/tuist lints code of target with name "(.+)" and fails/) do |target_name|
  _, err, status = Open3.capture3("swift", "run", "tuist", "lint", "code", target_name, "--path", @dir)
  flunk(err) if status.success?
end
