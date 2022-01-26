require_relative "../../test_helper"

module MinitestReportersTest
  class JUnitReporterTest < TestCase
    def test_replaces_special_characters_for_filenames_and_doesnt_crash
      fixtures_directory = File.expand_path('../../../fixtures', __FILE__)
      test_filename = File.join(fixtures_directory, 'junit_filename_bug_example_test.rb')
      output = `ruby #{test_filename} 2>&1`
      refute_match 'No such file or directory', output
    end
  end
end
