require_relative "../../test_helper"

module MinitestReportersTest
  class MinitestReporterPluginTest < Minitest::Test
    def test_delegates_io
      reporter = Minitest::Reporters::DefaultReporter.new
      io_handle = STDOUT
      dr = Minitest::Reporters::DelegateReporter.new([ reporter ], :io => io_handle)
      assert_equal io_handle, dr.io
      dr.send :all_reporters
      assert_equal io_handle, reporter.io
    end
  end
end
