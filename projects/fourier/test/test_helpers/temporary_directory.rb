# frozen_string_literal: true

module TestHelpers
  module TemporaryDirectory
    def setup
      super
      @tmp_dir = Dir.mktmpdir
      FileUtils.mkdir_p(@tmp_dir)
    end

    def teardown
      super
      FileUtils.rm_rf(@tmp_dir) if Dir.exist?(@tmp_dir)
    end
  end
end
