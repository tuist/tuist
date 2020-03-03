# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

And(/I have a working directory/) do
  @dir = Dir.mktmpdir
end

After do |_scenario|
  FileUtils.rm_r(@dir) unless @dir.nil?
end