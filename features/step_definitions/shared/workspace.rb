require 'tmpdir'
require 'fileutils'

And(/I have have a working directory/) do
  @dir = Dir.mktmpdir
end

Then(/I delete the working directory/) do
  FileUtils.rm_r(@dir)
end
