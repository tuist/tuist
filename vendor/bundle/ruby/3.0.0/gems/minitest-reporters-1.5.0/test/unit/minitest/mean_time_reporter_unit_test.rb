require_relative '../../test_helper'

module MinitestReportersTest
  class MeanTimeReporterUnitTest < Minitest::Test
    def setup
      @test_data = []
      @test_data << { name: 'MIDDLE',  prev_time: 5.0,  cur_time: 5.0 }
      @test_data << { name: 'MIN_FAST', prev_time: 0.5,  cur_time: 3.5 }
      @test_data << { name: 'MIN_SLOW', prev_time: 10.5, cur_time: 10.5 }
      @test_data << { name: 'MAX_FAST', prev_time: 1.2,  cur_time: 0.9 }
      @test_data << { name: 'MAX_SLOW', prev_time: 16.3, cur_time: 6.3 }
      @test_data << { name: 'AVG_FAST', prev_time: 1.3,  cur_time: 0.65 }
      @test_data << { name: 'AVG_SLOW', prev_time: 10.2, cur_time: 14.2 }
      configure_report_paths
    end

    def teardown
      File.delete(@previous_run_path) if File.exist?(@previous_run_path)
      File.delete(@report_file_path) if File.exist?(@report_file_path)
    end

    def test_defaults
      subject = Minitest::Reporters::MeanTimeReporter.new.send(:defaults)

      expected_prefix = "#{Dir.tmpdir}#{File::Separator}"
      assert_match expected_prefix, subject[:previous_runs_filename]
      assert_match expected_prefix, subject[:report_filename]
    end

    def test_sorts_avg_numerically
      prev_output = generate_report(:avg, :prev_time)
      report_output = generate_report(:avg, :cur_time)

      expected_order = [
        'AVG_SLOW',
        'MAX_SLOW',
        'MIN_SLOW',
        'MIDDLE',
        'MIN_FAST',
        'MAX_FAST',
        'AVG_FAST'
      ]
      verify_result_order(report_output, expected_order, prev_output)
    end

    def test_sorts_min_numerically
      prev_output = generate_report(:min, :prev_time)
      report_output = generate_report(:min, :cur_time)

      expected_order = [
        'MIN_SLOW',
        'AVG_SLOW',
        'MAX_SLOW',
        'MIDDLE',
        'MAX_FAST',
        'AVG_FAST',
        'MIN_FAST'
      ]
      verify_result_order(report_output, expected_order, prev_output)
    end

    def test_sorts_max_numerically
      prev_output = generate_report(:max, :prev_time)
      report_output = generate_report(:max, :cur_time)

      expected_order = [
        'MAX_SLOW',
        'AVG_SLOW',
        'MIN_SLOW',
        'MIDDLE',
        'MIN_FAST',
        'AVG_FAST',
        'MAX_FAST'
      ]
      verify_result_order(report_output, expected_order, prev_output)
    end

    def test_sorts_last_numerically
      prev_output = generate_report(:last, :prev_time)
      report_output = generate_report(:last, :cur_time)

      expected_order = [
        'AVG_SLOW',
        'MIN_SLOW',
        'MAX_SLOW',
        'MIDDLE',
        'MIN_FAST',
        'MAX_FAST',
        'AVG_FAST'
      ]
      verify_result_order(report_output, expected_order, prev_output)
    end

    private

    def simulate_suite_runtime(suite_name, run_time)
      test_suite = Minitest::Test.new(suite_name)
      base_clock_time = Minitest::Reporters.clock_time
      Minitest::Reporters.stub(:clock_time, base_clock_time - run_time) do
        @reporter.before_suite(test_suite)
      end
      Minitest::Reporters.stub(:clock_time, base_clock_time) do
        @reporter.after_suite(test_suite)
      end
    end

    def configure_report_paths
      @previous_run_path = File.expand_path("../minitest-mean-time-previous-runs",  File.realpath(__FILE__))
      File.delete(@previous_run_path) if File.exist?(@previous_run_path)
      @report_file_path = File.expand_path("../minitest-mean-time-report",  File.realpath(__FILE__))
      File.delete(@report_file_path) if File.exist?(@report_file_path)
    end

    def generate_report(sort_column, time_name)
      # Reset the reporter for the test run
      @reporter = Minitest::Reporters::MeanTimeReporter.new(
        previous_runs_filename: @previous_run_path,
        report_filename: @report_file_path,
        sort_column: sort_column
      )
      @test_data.each { |hash| simulate_suite_runtime(hash[:name], hash[time_name])}
      @reporter.tests << Minitest::Test.new('Final')

      report_output = StringIO.new
      @reporter.io = report_output
      @reporter.start
      @reporter.report
      report_output
    end

    def verify_result_order(report_output, expected_order, prev_output)
      prev_lines = extract_test_lines(prev_output)
      test_lines = extract_test_lines(report_output)

      actual_order = test_lines.map { |line| line.gsub(/.*Description: /, '') }

      assert_equal(expected_order, actual_order, "\nCurrent report:\n#{test_lines.join("\n")}\n\nPrevious report:\n#{prev_lines.join("\n")}")
    end

    def extract_test_lines(report_output)
      report_output.rewind
      test_lines = report_output.read.split("\n")
      test_lines.select! {|line| line.start_with?('Avg:')}
      # Exclude the final placeholder 0 second test from assertions
      test_lines.reject! {|line| line.end_with?('Minitest::Test')}
      test_lines
    end
  end
end
