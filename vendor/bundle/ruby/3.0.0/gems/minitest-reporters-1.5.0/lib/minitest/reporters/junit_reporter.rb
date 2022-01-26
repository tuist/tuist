# frozen_string_literal: true

require 'builder'
require 'fileutils'
require 'pathname'
require 'time'

module Minitest
  module Reporters
    # A reporter for writing JUnit test reports
    # Intended for easy integration with CI servers - tested on JetBrains TeamCity
    #
    # Inspired by ci_reporter (see https://github.com/nicksieger/ci_reporter)
    # Also inspired by Marc Seeger's attempt at producing a JUnitReporter (see https://github.com/rb2k/minitest-reporters/commit/e13d95b5f884453a9c77f62bc5cba3fa1df30ef5)
    # Also inspired by minitest-ci (see https://github.com/bhenderson/minitest-ci)
    class JUnitReporter < BaseReporter
      DEFAULT_REPORTS_DIR = "test/reports"

      attr_reader :reports_path

      def initialize(reports_dir = DEFAULT_REPORTS_DIR, empty = true, options = {})
        super({})
        @reports_path = File.absolute_path(ENV.fetch("MINITEST_REPORTERS_REPORTS_DIR", reports_dir))
        @single_file = options[:single_file]
        @base_path = options[:base_path] || Dir.pwd
        @timestamp_report = options[:include_timestamp]

        return unless empty

        puts "Emptying #{@reports_path}"
        FileUtils.mkdir_p(@reports_path)
        File.delete(*Dir.glob("#{@reports_path}/TEST-*.xml"))
      end

      def report
        super

        puts "Writing XML reports to #{@reports_path}"
        suites = tests.group_by do |test|
          test_class(test)
        end

        if @single_file
          xml = Builder::XmlMarkup.new(:indent => 2)
          xml.instruct!
          xml.testsuites do
            suites.each do |suite, tests|
              parse_xml_for(xml, suite, tests)
            end
          end
          File.open(filename_for('minitest'), "w") { |file| file << xml.target! }
        else
          suites.each do |suite, tests|
            xml = Builder::XmlMarkup.new(:indent => 2)
            xml.instruct!
            xml.testsuites do
              parse_xml_for(xml, suite, tests)
            end
            File.open(filename_for(suite), "w") { |file| file << xml.target! }
          end
        end
      end

      def get_relative_path(result)
        file_path = Pathname.new(get_source_location(result).first)
        base_path = Pathname.new(@base_path)

        if file_path.absolute?
          file_path.relative_path_from(base_path)
        else
          file_path
        end
      end

      private

      def get_source_location(result)
        if result.respond_to? :source_location
          result.source_location
        else
          result.method(result.name).source_location
        end
      end

      def parse_xml_for(xml, suite, tests)
        suite_result = analyze_suite(tests)
        file_path = get_relative_path(tests.first)

        if @timestamp_report
          xml.testsuite(:name => suite, :filepath => file_path,
                                    :skipped => suite_result[:skip_count], :failures => suite_result[:fail_count],
                                    :errors => suite_result[:error_count], :tests => suite_result[:test_count],
                                    :assertions => suite_result[:assertion_count], :time => suite_result[:time],
                                    :timestamp => suite_result[:timestamp]) do
            tests.each do |test|
              lineno = get_source_location(test).last
              xml.testcase(:name => test.name, :lineno => lineno, :classname => suite, :assertions => test.assertions,
                           :time => test.time, :file => file_path) do
                xml << xml_message_for(test) unless test.passed?
              end
            end
          end
        else
         xml.testsuite(:name => suite, :filepath => file_path,
                                    :skipped => suite_result[:skip_count], :failures => suite_result[:fail_count],
                                    :errors => suite_result[:error_count], :tests => suite_result[:test_count],
                                    :assertions => suite_result[:assertion_count], :time => suite_result[:time]) do
            tests.each do |test|
              lineno = get_source_location(test).last
              xml.testcase(:name => test.name, :lineno => lineno, :classname => suite, :assertions => test.assertions,
                           :time => test.time, :file => file_path) do
                xml << xml_message_for(test) unless test.passed?
              end
            end
          end
        end
      end

      def xml_message_for(test)
        # This is a trick lifted from ci_reporter
        xml = Builder::XmlMarkup.new(:indent => 2, :margin => 2)

        def xml.trunc!(txt)
          txt.sub(/\n.*/m, '...')
        end

        failure = test.failure

        if test.skipped?
          xml.skipped(:type => failure.error.class.name)
        elsif test.error?
          xml.error(:type => failure.error.class.name, :message => xml.trunc!(failure.message)) do
            xml.text!(message_for(test))
          end
        elsif failure
          xml.failure(:type => failure.error.class.name, :message => xml.trunc!(failure.message)) do
            xml.text!(message_for(test))
          end
        end
      end

      def message_for(test)
        suite = test.class
        name = test.name
        e = test.failure

        if test.passed?
          nil
        elsif test.skipped?
          "Skipped:\n#{name}(#{suite}) [#{location(e)}]:\n#{e.message}\n"
        elsif test.failure
          "Failure:\n#{name}(#{suite}) [#{location(e)}]:\n#{e.message}\n"
        elsif test.error?
          "Error:\n#{name}(#{suite}):\n#{e.message}"
        end
      end

      def location(exception)
        last_before_assertion = ''
        exception.backtrace.reverse_each do |s|
          break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/

          last_before_assertion = s
        end
        last_before_assertion.sub(/:in .*$/, '')
      end

      def analyze_suite(tests)
        result = Hash.new(0)
        result[:time] = 0
        tests.each do |test|
          result[:"#{result(test)}_count"] += 1
          result[:assertion_count] += test.assertions
          result[:test_count] += 1
          result[:time] += test.time
          result[:timestamp] = Time.now.iso8601 if @timestamp_report
        end
        result
      end

      def filename_for(suite)
        file_counter = 0
        # restrict max filename length, to be kind to filesystems
        suite_name = suite.to_s[0..240].gsub(/[^a-zA-Z0-9]+/, '-')
        filename = "TEST-#{suite_name}.xml"
        while File.exist?(File.join(@reports_path, filename)) # restrict number of tries, to avoid infinite loops
          file_counter += 1
          filename = "TEST-#{suite_name}-#{file_counter}.xml"
          if file_counter >= 99
            puts "Too many duplicate files, overwriting earlier report #{filename}"
            break
          end
        end
        File.join(@reports_path, filename)
      end
    end
  end
end
