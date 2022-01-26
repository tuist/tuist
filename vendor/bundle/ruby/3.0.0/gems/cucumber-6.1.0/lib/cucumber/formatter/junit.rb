# frozen_string_literal: true

require 'builder'
require 'cucumber/formatter/backtrace_filter'
require 'cucumber/formatter/io'
require 'cucumber/formatter/interceptor'
require 'fileutils'
require 'cucumber/formatter/ast_lookup'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format junit</tt>
    class Junit
      include Io

      class UnNamedFeatureError < StandardError
        def initialize(feature_file)
          super("The feature in '#{feature_file}' does not have a name. The JUnit XML format requires a name for the testsuite element.")
        end
      end

      def initialize(config)
        @ast_lookup = AstLookup.new(config)
        config.on_event :test_case_started, &method(:on_test_case_started)
        config.on_event :test_case_finished, &method(:on_test_case_finished)
        config.on_event :test_step_finished, &method(:on_test_step_finished)
        config.on_event :test_run_finished, &method(:on_test_run_finished)
        @reportdir = ensure_dir(config.out_stream, 'junit')
        @config = config
        @features_data = Hash.new do |h, k|
          h[k] = {
            feature: nil,
            failures: 0,
            errors: 0,
            tests: 0,
            skipped: 0,
            time: 0,
            builder: Builder::XmlMarkup.new(indent: 2)
          }
        end
      end

      def on_test_case_started(event)
        test_case = event.test_case
        start_feature(test_case) unless same_feature_as_previous_test_case?(test_case)
        @failing_test_step = nil
        # In order to fill out <system-err/> and <system-out/>, we need to
        # intercept the $stderr and $stdout
        @interceptedout = Interceptor::Pipe.wrap(:stdout)
        @interceptederr = Interceptor::Pipe.wrap(:stderr)
      end

      def on_test_step_finished(event)
        test_step, result = *event.attributes
        return if @failing_test_step

        @failing_test_step = test_step unless result.ok?(@config.strict)
      end

      def on_test_case_finished(event)
        test_case, result = *event.attributes
        result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
        test_case_name = NameBuilder.new(test_case, @ast_lookup)
        scenario = test_case_name.scenario_name
        scenario_designation = "#{scenario}#{test_case_name.name_suffix}"
        output = create_output_string(test_case, scenario, result, test_case_name.row_name)
        build_testcase(result, scenario_designation, output)

        Interceptor::Pipe.unwrap! :stdout
        Interceptor::Pipe.unwrap! :stderr
      end

      def on_test_run_finished(_event)
        @features_data.each { |_file, data| end_feature(data) }
      end

      private

      def same_feature_as_previous_test_case?(test_case)
        @current_feature_data && @current_feature_data[:uri] == test_case.location.file
      end

      def start_feature(test_case)
        uri = test_case.location.file
        feature = @ast_lookup.gherkin_document(uri).feature
        raise UnNamedFeatureError, uri if feature.name.empty?
        @current_feature_data = @features_data[uri]
        @current_feature_data[:uri] = uri unless @current_feature_data[:uri]
        @current_feature_data[:feature] = feature unless @current_feature_data[:feature]
      end

      def end_feature(feature_data)
        @testsuite = Builder::XmlMarkup.new(indent: 2)
        @testsuite.instruct!
        @testsuite.testsuite(
          failures: feature_data[:failures],
          errors: feature_data[:errors],
          skipped: feature_data[:skipped],
          tests: feature_data[:tests],
          time: format('%<time>.6f', time: feature_data[:time]),
          name: feature_data[:feature].name
        ) do
          @testsuite << feature_data[:builder].target!
        end

        write_file(feature_result_filename(feature_data[:uri]), @testsuite.target!)
      end

      def create_output_string(test_case, scenario, result, row_name)
        scenario_source = @ast_lookup.scenario_source(test_case)
        keyword = scenario_source.type == :Scenario ? scenario_source.scenario.keyword : scenario_source.scenario_outline.keyword
        output = "#{keyword}: #{scenario}\n\n"
        return output if result.ok?(@config.strict)
        if scenario_source.type == :Scenario
          if @failing_test_step
            if @failing_test_step.hook?
              output += "#{@failing_test_step.text} at #{@failing_test_step.location}\n"
            else
              step_source = @ast_lookup.step_source(@failing_test_step).step
              output += "#{step_source.keyword}#{@failing_test_step.text}\n"
            end
          else # An Around hook has failed
            output += "Around hook\n"
          end
        else
          output += "Example row: #{row_name}\n"
        end
        output + "\nMessage:\n"
      end

      def build_testcase(result, scenario_designation, output)
        duration = ResultBuilder.new(result).test_case_duration
        @current_feature_data[:time] += duration
        classname = @current_feature_data[:feature].name
        filename = @current_feature_data[:uri]
        name = scenario_designation

        testcase_attributes = get_testcase_attributes(classname, name, duration, filename)

        @current_feature_data[:builder].testcase(testcase_attributes) do
          if !result.passed? && result.ok?(@config.strict)
            @current_feature_data[:builder].skipped
            @current_feature_data[:skipped] += 1
          elsif !result.passed?
            status = result.to_sym
            exception = get_backtrace_object(result)
            @current_feature_data[:builder].failure(message: "#{status} #{name}", type: status) do
              @current_feature_data[:builder].cdata! output
              @current_feature_data[:builder].cdata!(format_exception(exception)) if exception
            end
            @current_feature_data[:failures] += 1
          end
          @current_feature_data[:builder].tag!('system-out') do
            @current_feature_data[:builder].cdata! strip_control_chars(@interceptedout.buffer_string)
          end
          @current_feature_data[:builder].tag!('system-err') do
            @current_feature_data[:builder].cdata! strip_control_chars(@interceptederr.buffer_string)
          end
        end
        @current_feature_data[:tests] += 1
      end

      def get_testcase_attributes(classname, name, duration, filename)
        { classname: classname, name: name, time: format('%<duration>.6f', duration: duration) }.tap do |attributes|
          attributes[:file] = filename if add_fileattribute?
        end
      end

      def add_fileattribute?
        return false if @config.formats.nil? || @config.formats.empty?

        !!@config.formats.find do |format|
          format.first == 'junit' && format.dig(1, 'fileattribute') == 'true'
        end
      end

      def get_backtrace_object(result)
        if result.failed?
          result.exception
        elsif result.backtrace
          result
        end
      end

      def format_exception(exception)
        (["#{exception.message} (#{exception.class})"] + exception.backtrace).join("\n")
      end

      def feature_result_filename(feature_file)
        File.join(@reportdir, "TEST-#{basename(feature_file)}.xml")
      end

      def basename(feature_file)
        File.basename(feature_file.gsub(/[\\\/]/, '-'), '.feature') # rubocop:disable Style/RegexpLiteral
      end

      def write_file(feature_filename, data)
        File.open(feature_filename, 'w') { |file| file.write(data) }
      end

      # strip control chars from cdata, to make it safe for external parsers
      def strip_control_chars(cdata)
        cdata.scan(/[[:print:]\t\n\r]/).join
      end
    end

    class NameBuilder
      attr_reader :scenario_name, :name_suffix, :row_name

      def initialize(test_case, ast_lookup)
        @name_suffix = ''
        @row_name = ''
        scenario_source = ast_lookup.scenario_source(test_case)
        if scenario_source.type == :Scenario
          scenario(scenario_source.scenario)
        else
          scenario_outline(scenario_source.scenario_outline)
          examples_table_row(scenario_source.row)
        end
      end

      def scenario(scenario)
        @scenario_name = scenario.name.empty? ? 'Unnamed scenario' : scenario.name
      end

      def scenario_outline(outline)
        @scenario_name = outline.name.empty? ? 'Unnamed scenario outline' : outline.name
      end

      def examples_table_row(row)
        @row_name = '| ' + row.cells.map(&:value).join(' | ') + ' |'
        @name_suffix = " (outline example : #{@row_name})"
      end
    end

    class ResultBuilder
      attr_reader :test_case_duration
      def initialize(result)
        @test_case_duration = 0
        result.describe_to(self)
      end

      def passed(*) end

      def failed(*) end

      def undefined(*) end

      def skipped(*) end

      def pending(*) end

      def exception(*) end

      def duration(duration, *)
        duration.tap { |dur| @test_case_duration = dur.nanoseconds / 10**9.0 }
      end

      def attach(*) end
    end
  end
end
