# frozen_string_literal: true

addpath = lambda do |p|
  $LOAD_PATH.unshift(p) unless $LOAD_PATH.include?(p)
end
addpath.call(File.expand_path("../lib", __dir__))

require "cli/ui"
require "fileutils"
require "tmpdir"
require "tempfile"
require "byebug"

Dir.glob(File.join(__dir__, "test_helpers/*")).each { |f| require(f) }

CLI::UI::StdoutRouter.enable

require "minitest/autorun"
require "minitest/unit"
require "minitest/reporters"

reporter_options = { color: true }
Minitest::Reporters.use!([Minitest::Reporters::DefaultReporter.new(reporter_options)])

require "mocha/minitest"

require "fourier"

class TestCase < MiniTest::Test
  def root_directory
    File.expand_path("../../..", __dir__)
  end
end
