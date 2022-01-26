require 'minitest/reporters'
require 'tmpdir'
require 'yaml'

module Minitest
  module Reporters
    # This reporter creates a report providing the average (mean), minimum and
    # maximum times for a test to run. Running this for all your tests will
    # allow you to:
    #
    # 1) Identify the slowest running tests over time as potential candidates
    #    for improvements or refactoring.
    # 2) Identify (and fix) regressions in test run speed caused by changes to
    #    your tests or algorithms in your code.
    # 3) Provide an abundance of statistics to enjoy.
    #
    # This is achieved by creating a (configurable) 'previous runs' statistics
    # file which is parsed at the end of each run to provide a new
    # (configurable) report. These statistics can be reset at any time by using
    # a simple rake task:
    #
    #     rake reset_statistics
    #
    class MeanTimeReporter < Minitest::Reporters::DefaultReporter
      class InvalidOrder < StandardError; end
      class InvalidSortColumn < StandardError; end

      # Reset the statistics file for this reporter. Called via a rake task:
      #
      #     rake reset_statistics
      #
      # @return [Boolean]
      def self.reset_statistics!
        new.reset_statistics!
      end

      # @param options [Hash]
      # @option previous_runs_filename [String] Contains the times for each test
      #   by description. Defaults to '/tmp/minitest_reporters_previous_run'.
      # @option report_filename [String] Contains the parsed results for the
      #   last test run. Defaults to '/tmp/minitest_reporters_report'.
      # @option show_count [Fixnum] The number of tests to show in the report
      #   summary at the end of the test run. Default is 15.
      # @option show_progress [Boolean] If true it prints pass/skip/fail marks.
      #   Default is true.
      # @option show_all_runs [Boolean] If true it shows all recorded suit results.
      #   Default is true.
      # @option sort_column [Symbol] One of :avg (default), :min, :max, :last.
      #   Determines the column by which the report summary is sorted.
      # @option order [Symbol] One of :desc (default), or :asc. By default the
      #   report summary is listed slowest to fastest (:desc). :asc will order
      #   the report summary as fastest to slowest.
      # @return [Minitest::Reporters::MeanTimeReporter]
      def initialize(options = {})
        super

        @all_suite_times = []
      end

      # Copies the suite times from the
      # {Minitest::Reporters::DefaultReporter#after_suite} method, making them
      # available to this class.
      #
      # @return [Hash<String => Float>]
      def after_suite(suite)
        super

        @all_suite_times = @suite_times
      end

      # Runs the {Minitest::Reporters::DefaultReporter#report} method and then
      # enhances it by storing the results to the 'previous_runs_filename' and
      # outputs the parsed results to both the 'report_filename' and the
      # terminal.
      #
      def report
        super

        create_or_update_previous_runs!

        create_new_report!

        write_to_screen!
      end

      def on_start
        super if options[:show_progress]
      end

      def on_record(test)
        super if options[:show_progress]
      end

      def on_report
        super if options[:show_progress]
      end

      # Resets the 'previous runs' file, essentially removing all previous
      # statistics gathered.
      #
      # @return [void]
      def reset_statistics!
        File.delete(previous_runs_filename) if File.exist?(previous_runs_filename)
      end

      protected

      attr_accessor :all_suite_times

      private

      # @return [Hash<String => Float>]
      def current_run
        Hash[all_suite_times]
      end

      # @return [Hash] Sets default values for the filenames used by this class,
      #   and the number of tests to output to output to the screen after each
      #   run.
      def defaults
        {
          order:                  :desc,
          show_count:             15,
          show_progress:          true,
          show_all_runs:          true,
          sort_column:            :avg,
          previous_runs_filename: File.join(Dir.tmpdir, 'minitest_reporters_previous_run'),
          report_filename:        File.join(Dir.tmpdir, 'minitest_reporters_report'),
        }
      end

      # Added to the top of the report file and to the screen output.
      #
      # @return [String]
      def report_title
        "\n\e[4mMinitest Reporters: Mean Time Report\e[24m " \
        "(Samples: #{samples}, Order: #{sort_column.inspect} " \
        "#{order.inspect})\n"
      end

      # The report itself. Displays statistics about all runs, ideal for use
      # with the Unix 'head' command. Listed in slowest average descending
      # order.
      #
      # @return [String]
      def report_body
        order_sorted_body.each_with_object([]) do |result, obj|
          rating = rate(result[:last], result[:min], result[:max])

          obj << "#{avg_label} #{result[:avg].to_s.ljust(12)} " \
                 "#{min_label} #{result[:min].to_s.ljust(12)} " \
                 "#{max_label} #{result[:max].to_s.ljust(12)} " \
                 "#{run_label(rating)} #{result[:last].to_s.ljust(12)} " \
                 "#{des_label} #{result[:desc]}\n"
        end.join
      end

      # @return [String] All of the column-sorted results sorted by the :order
      #   option. (Defaults to :desc).
      def order_sorted_body
        if desc?
          column_sorted_body.reverse

        elsif asc?
          column_sorted_body

        end
      end

      # @return [Array<Hash<Symbol => String>>] All of the results sorted by
      #   the :sort_column option. (Defaults to :avg).
      def column_sorted_body
        runs = options[:show_all_runs] ? previous_run : current_run
        runs.keys.each_with_object([]) do |description, obj|
          timings = previous_run[description]
          size = Array(timings).size
          sum  = Array(timings).inject { |total, x| total + x }
          obj << {
            avg:  (sum / size).round(9),
            min:  Array(timings).min.round(9),
            max:  Array(timings).max.round(9),
            last: Array(timings).last.round(9),
            desc: description,
          }
        end.sort_by { |k| k[sort_column] }
      end

      # @return [Hash]
      def options
        defaults.merge!(@options)
      end

      # @return [Fixnum] The number of tests to output to output to the screen
      #   after each run.
      def show_count
        options[:show_count]
      end

      # @return [Hash<String => Array<Float>]
      def previous_run
        @previous_run ||= YAML.load_file(previous_runs_filename)
      end

      # @return [String] The path to the file which contains all the durations
      #   for each test run. The previous runs file is in YAML format, using the
      #   test name for the key and an array containing the time taken to run
      #   this test for values.
      def previous_runs_filename
        options[:previous_runs_filename]
      end

      # Returns a boolean indicating whether a previous runs file exists.
      #
      # @return [Boolean]
      def previously_ran?
        File.exist?(previous_runs_filename)
      end

      # @return [String] The path to the file which contains the parsed test
      #   results. The results file contains a line for each test with the
      #   average time of the test, the minimum time the test took to run,
      #   the maximum time the test took to run and a description of the test
      #   (which is the test name as emitted by Minitest).
      def report_filename
        options[:report_filename]
      end

      # A barbaric way to find out how many runs are in the previous runs file;
      # this method takes the first test listed, and counts its samples
      # trusting (naively) all runs to be the same number of samples. This will
      # produce incorrect averages when new tests are added, so it is advised
      # to restart the statistics by removing the 'previous runs' file. A rake
      # task is provided to make this more convenient.
      #
      #    rake reset_statistics
      #
      # @return [Fixnum]
      def samples
        return 1 unless previous_run.first[1].is_a?(Array)

        previous_run.first[1].size
      end

      # Creates a new 'previous runs' file, or updates the existing one with
      # the latest timings.
      #
      # @return [void]
      def create_or_update_previous_runs!
        if previously_ran?
          current_run.each do |description, elapsed|
            new_times = if previous_run[description.to_s]
                          Array(previous_run[description.to_s]) << elapsed
                        else
                          Array(elapsed)
                        end

            previous_run.store(description.to_s, new_times)
          end

          File.write(previous_runs_filename, previous_run.to_yaml)

        else

          File.write(previous_runs_filename, current_run.to_yaml)

        end
      end

      # Creates a new report file in the 'report_filename'. This file contains
      # a line for each test of the following example format: (this is a single
      # line despite explicit wrapping)
      #
      # Avg: 0.0555555 Min: 0.0498765 Max: 0.0612345 Last: 0.0499421
      # Description: The test name
      #
      # Note however the timings are to 9 decimal places, and padded to 12
      # characters and each label is coloured, Avg (yellow), Min (green),
      # Max (red), Last (multi), and Description (blue). It looks pretty!
      #
      # The 'Last' label is special in that it will be colour coded depending
      # on whether the last run was faster (bright green) or slower (bright red)
      # or inconclusive (purple). This helps to identify changes on a per run
      # basis.
      #
      # @return [void]
      def create_new_report!
        File.write(report_filename, report_title + report_body)
      end

      # Writes a number of tests (configured via the 'show_count' option) to the
      # screen after creating the report. See '#create_new_report!' for example
      # output information.
      #
      # @return [void]
      def write_to_screen!
        puts report_title
        puts report_body.lines.take(show_count)
      end

      # @return [String] A yellow 'Avg:' label.
      def avg_label
        ANSI::Code.yellow('Avg:')
      end

      # @return [String] A blue 'Description:' label.
      def des_label
        ANSI::Code.blue('Description:')
      end

      # @return [String] A red 'Max:' label.
      def max_label
        ANSI::Code.red('Max:')
      end

      # @return [String] A green 'Min:' label.
      def min_label
        ANSI::Code.green('Min:')
      end

      # @param rating [Symbol] One of :faster, :slower or :inconclusive.
      # @return [String] A purple 'Last:' label.
      def run_label(rating)
        case rating
        when :faster then ANSI::Code.green('Last:')
        when :slower then ANSI::Code.red('Last:')
        else
          ANSI::Code.magenta('Last:')
        end
      end

      # @param run [Float] The last run time.
      # @param min [Float] The minimum run time.
      # @param max [Float] The maximum run time.
      # @return [Symbol] One of :faster, :slower or :inconclusive.
      def rate(run, min, max)
        if run == min
          :faster
        elsif run == max
          :slower
        else
          :inconclusive
        end
      end

      # @return [Boolean] Whether the given :order option is :asc.
      def asc?
        order == :asc
      end

      # @return [Boolean] Whether the given :order option is :desc (default).
      def desc?
        order == :desc
      end

      # @raise [Minitest::Reporters::MeanTimeReporter::InvalidOrder]
      #   When the given :order option is invalid.
      # @return [Symbol] The :order option, or by default; :desc.
      def order
        orders = [:desc, :asc]

        if orders.include?(options[:order])
          options[:order]

        else
          fail Minitest::Reporters::MeanTimeReporter::InvalidOrder,
               "`:order` option must be one of #{orders.inspect}."

        end
      end

      # @raise [Minitest::Reporters::MeanTimeReporter::InvalidSortColumn]
      #   When the given :sort_column option is invalid.
      # @return [Symbol] The :sort_column option, or by default; :avg.
      def sort_column
        sort_columns = [:avg, :min, :max, :last]

        if sort_columns.include?(options[:sort_column])
          options[:sort_column]

        else
          fail Minitest::Reporters::MeanTimeReporter::InvalidSortColumn,
               "`:sort_column` option must be one of #{sort_columns.inspect}."

        end
      end
    end
  end
end
