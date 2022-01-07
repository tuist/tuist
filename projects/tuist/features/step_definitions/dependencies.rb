# frozen_string_literal: true

Then(/tuist fetches dependencies/) do
  system(@tuist, "fetch", "dependencies", "--path", @dir)
end

Then(/tuist updates dependencies/) do
  system(@tuist, "fetch", "dependencies", "--update", "--path", @dir)
end
