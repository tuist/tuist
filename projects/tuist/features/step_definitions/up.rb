# frozen_string_literal: true

Then(/I should have (.+) installed/) do |tool_path|
  @tool_path = tool_path
  assert(File.exist?(tool_path), "#{tool_path} was not installed")
end

After do
  FileUtils.rm_r(@tool_path) unless @tool_path.nil?
end
