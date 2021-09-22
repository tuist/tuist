# frozen_string_literal: true

require "tmpdir"
require "fileutils"

And(/I have a working directory/) do
  @dir = Dir.mktmpdir
  @cache_dir = Dir.mktmpdir
  @derived_data_path = Dir.mktmpdir
  ENV["TUIST_CONFIG_FORCE_CONFIG_CACHE_DIRECTORY"] = @cache_dir
  ENV["TUIST_CONFIG_AUTOMATION_PATH"] = File.join(@dir, "Automation")
end

After do |_scenario|
  FileUtils.rm_r(@dir) unless @dir.nil?
  FileUtils.rm_r(@cache_dir) unless @cache_dir.nil?
  FileUtils.rm_r(@derived_data_path) unless @derived_data_path.nil?
end
