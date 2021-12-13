# frozen_string_literal: true

Then(/tuist does fetch/) do
  output, err, status = Open3.capture3(@tuist, "fetch", "--path", @dir)
  puts output
  flunk(err) unless status.success?
end
