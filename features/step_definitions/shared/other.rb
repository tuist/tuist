# frozen_string_literal: true
Then(/I add an empty line at the end of the file (.+)/) do |file_path|
  path = File.join(@dir, file_path)
  open(path, "a") { |f| f.puts "\n" }
end
