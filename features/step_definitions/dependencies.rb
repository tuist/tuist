# frozen_string_literal: true
Then(/tuist fetches dependencies/) do
  out, err, status = Open3.capture3("swift", "run", "tuist", "dependencies", "fetch", "--path", @dir)
  flunk(err) unless status.success?
end

Then(/tuist updates dependencies/) do
  out, err, status = Open3.capture3("swift", "run", "tuist", "dependencies", "update", "--path", @dir)
  flunk(err) unless status.success?
end
