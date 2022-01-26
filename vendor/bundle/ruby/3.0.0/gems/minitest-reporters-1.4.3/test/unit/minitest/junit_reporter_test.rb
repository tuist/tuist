require_relative "../../test_helper"

module MinitestReportersTest
  class JUnitReporterUnitTest < Minitest::Test
    def setup
      @reporter = Minitest::Reporters::JUnitReporter.new(
          "report",
          false,
          :base_apath => Dir.pwd
      )
      @result = Minitest::Result.new("test_name")
    end

    def test_relative_path
      path = Pathname.new(__FILE__).relative_path_from(Pathname.new(Dir.pwd)).to_s
      @result.source_location = [path, 10]
      relative_path = @reporter.get_relative_path(@result)
      assert_equal path, relative_path.to_s
    end

    def test_defaults_reports_path
      reporter = Minitest::Reporters::JUnitReporter.new
      expected_reports_dir = Minitest::Reporters::JUnitReporter::DEFAULT_REPORTS_DIR
      expected_reports_path = File.absolute_path(expected_reports_dir)
      assert_equal expected_reports_path, reporter.reports_path
    end

    def test_accepts_custom_report_dir_using_env
      expected_reports_dir = "test_reports"
      expected_reports_path = File.absolute_path(expected_reports_dir)
      with_env("MINITEST_REPORTERS_REPORTS_DIR" => expected_reports_dir) do
        reporter = Minitest::Reporters::JUnitReporter.new
        assert_equal expected_reports_path, reporter.reports_path
      end
    end

    private

    def with_env(hash)
      original_env = ENV.to_hash
      ENV.update(hash)
      yield
      ENV.replace(original_env)
    end
  end
end
