require 'tmpdir'
require 'fileutils'

module TemporaryDirectory
  def setup
    super
    @tmp_dir = Dir.mktmpdir
  end

  def teardown
    super
    FileUtils.rm_rf(@tmp_dir) if Dir.exist?(@tmp_dir)
  end
end
