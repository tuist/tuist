require_relative "../../test_helper"

module MinitestReportersTest
  class ProgressReporterTest < TestCase
    def test_all_failures_are_displayed
      fixtures_directory = File.expand_path('../../../fixtures', __FILE__)
      test_filename = File.join(fixtures_directory, 'progress_test.rb')
      output = `#{ruby_executable} #{test_filename} 2>&1`
      assert_match 'test_error', output, 'Errors should be displayed'
      assert_match 'test_failure', output, 'Failures should be displayed'
      assert_match 'test_skip', output, 'Skipped tests should be displayed'
    end
    def test_skipped_tests_are_not_displayed
      fixtures_directory = File.expand_path('../../../fixtures', __FILE__)
      test_filename = File.join(fixtures_directory, 'progress_detailed_skip_test.rb')
      output = `#{ruby_executable} #{test_filename} 2>&1`
      assert_match 'test_error', output, 'Errors should be displayed'
      assert_match 'test_failure', output, 'Failures should be displayed'
      refute_match 'test_skip', output, 'Skipped tests should not be displayed'
    end
    def test_progress_works_with_filter_and_specs
      fixtures_directory = File.expand_path('../../../fixtures', __FILE__)
      test_filename = File.join(fixtures_directory, 'spec_test.rb')
      output = `#{ruby_executable} #{test_filename} -n /length/ 2>&1`
      refute_match '0 out of 0', output, 'Progress should not puts a warning'
    end
    def test_progress_works_with_strict_filter
      fixtures_directory = File.expand_path('../../../fixtures', __FILE__)
      test_filename = File.join(fixtures_directory, 'spec_test.rb')
      output = `#{ruby_executable} #{test_filename} -n /^test_0001_works$/ 2>&1`
      refute_match '0 out of 0', output, 'Progress should not puts a warning'
    end

    private

    def ruby_executable
      defined?(JRUBY_VERSION) ? 'jruby' : 'ruby'
    end
  end
end
