# frozen_string_literal: true

Then(/^tuist builds the plugin$/) do
  system(@tuist, "plugin", "build", "--path", @dir)
end

Then(/^tuist runs plugin's task ([a-zA-Z\-]+)$/) do |task|
  system(@tuist, "plugin", "run", "--path", @dir, task)
end

Then(/^tuist tests the plugin$/) do
  system(@tuist, "plugin", "test", "--path", @dir)
end
