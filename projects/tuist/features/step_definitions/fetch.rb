# frozen_string_literal: true

Then(/tuist does fetch/) do
  _, err, status = Open3.capture3(@tuist, "fetch", "--path", @dir)
  flunk(err) unless status.success?
end
