# frozen_string_literal: true

Then(/tuist lints project's code and passes/) do
  system(@tuist, "lint", "code", "--path", @dir)
end

Then(/tuist lints project's code and fails/) do
  system(@tuist, "lint", "code", "--path", @dir)
end

Then(/tuist lints code of target with name "(.+)" and passes/) do |target_name|
  system(@tuist, "lint", "code", target_name, "--path", @dir)
end

Then(/tuist strict lints code of target with name "(.+)" and fails/) do |target_name|
  system(@tuist, "lint", "code", target_name, "--path", @dir, "--strict")
end

Then(/tuist lints code of target with name "(.+)" and fails/) do |target_name|
  system(@tuist, "lint", "code", target_name, "--path", @dir)
end
