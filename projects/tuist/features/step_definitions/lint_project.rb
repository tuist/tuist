# frozen_string_literal: true

Then(/tuist lints the project and fails/) do
  system(@tuist, "lint", "project", "--path", @dir)
end
