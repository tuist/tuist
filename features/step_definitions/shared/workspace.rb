# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

And(/I have a working directory/) do
  @dir = Dir.mktmpdir
end

After do |scenario|
  if scenario.failed? && !@dir.nil?
    tmp_dir = Dir.mktmpdir
    FileUtils.cp_r(@dir, tmp_dir)
    puts "The failing working directory has been copied into: #{tmp_dir}"
  end
  FileUtils.rm_r(@dir) unless @dir.nil?
end
