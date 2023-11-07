# frozen_string_literal: true

Then(/tuist fetches dependencies/) do
  system(@tuist, "fetch", "--path", @dir)
end

Then(/tuist updates dependencies/) do
  system(@tuist, "fetch", "--update", "--path", @dir)
end
