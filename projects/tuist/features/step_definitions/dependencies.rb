# frozen_string_literal: true

Then(/tuist fetches dependencies/) do
  system(@tuist, "dependencies", "fetch", "--path", @dir)
end

Then(/tuist updates dependencies/) do
  system(@tuist, "dependencies", "update", "--path", @dir)
end
