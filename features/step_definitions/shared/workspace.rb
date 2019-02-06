# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

And(/I have have a working directory/) do
  @dir = Dir.mktmpdir
end

After do
  FileUtils.rm_r(@dir) unless @dir.nil?
end
