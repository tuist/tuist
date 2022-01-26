# frozen_string_literal: true

require 'fileutils'
require 'cucumber/configuration'
require 'cucumber/create_meta'
require 'cucumber/load_path'
require 'cucumber/formatter/duration'
require 'cucumber/file_specs'
require 'cucumber/filters'
require 'cucumber/formatter/fanout'
require 'cucumber/gherkin/i18n'
require 'cucumber/step_match_search'
require 'cucumber/messages'
require 'sys/uname'

module Cucumber
  module FixRuby21Bug9285
    def message
      String(super).gsub('@ rb_sysopen ', '')
    end
  end

  class FileException < RuntimeError
    attr_reader :path

    def initialize(original_exception, path)
      super(original_exception)
      @path = path
    end
  end

  class FileNotFoundException < FileException
  end

  class FeatureFolderNotFoundException < RuntimeError
    def initialize(path)
      @path = path
    end

    def message
      "No such file or directory - #{@path}"
    end
  end

  require 'cucumber/core'
  require 'cucumber/runtime/user_interface'
  require 'cucumber/runtime/support_code'
  class Runtime
    attr_reader :results, :support_code, :configuration

    include Cucumber::Core
    include Formatter::Duration
    include Runtime::UserInterface

    def initialize(configuration = Configuration.default)
      @configuration = Configuration.new(configuration)
      @support_code = SupportCode.new(self, @configuration)
    end

    # Allows you to take an existing runtime and change its configuration
    def configure(new_configuration)
      @configuration = Configuration.new(new_configuration)
      @support_code.configure(@configuration)
    end

    require 'cucumber/wire/plugin'
    def run!
      @configuration.notify :envelope, Cucumber::Messages::Envelope.new(
        meta: Cucumber::CreateMeta.create_meta('cucumber-ruby', Cucumber::VERSION)
      )

      load_step_definitions
      install_wire_plugin
      fire_after_configuration_hook
      # TODO: can we remove this state?
      self.visitor = report

      receiver = Test::Runner.new(@configuration.event_bus)
      compile features, receiver, filters, @configuration.event_bus
      @configuration.notify :test_run_finished
    end

    def features_paths
      @configuration.paths
    end

    def dry_run?
      @configuration.dry_run?
    end

    def unmatched_step_definitions
      @support_code.unmatched_step_definitions
    end

    def begin_scenario(test_case)
      @support_code.fire_hook(:begin_scenario, test_case)
    end

    def end_scenario(_scenario)
      @support_code.fire_hook(:end_scenario)
    end

    # Returns Ast::DocString for +string_without_triple_quotes+.
    #
    def doc_string(string_without_triple_quotes, content_type = '', _line_offset = 0)
      Core::Test::DocString.new(string_without_triple_quotes, content_type)
    end

    private

    def fire_after_configuration_hook #:nodoc:
      @support_code.fire_hook(:after_configuration, @configuration)
    end

    require 'cucumber/core/gherkin/document'
    def features
      @features ||= feature_files.map do |path|
        source = NormalisedEncodingFile.read(path)
        @configuration.notify :gherkin_source_read, path, source
        Cucumber::Core::Gherkin::Document.new(path, source)
      end
    end

    def feature_files
      filespecs.files
    end

    def filespecs
      @filespecs ||= FileSpecs.new(@configuration.feature_files)
    end

    class NormalisedEncodingFile
      COMMENT_OR_EMPTY_LINE_PATTERN = /^\s*#|^\s*$/ #:nodoc:
      ENCODING_PATTERN = /^\s*#\s*encoding\s*:\s*([^\s]+)/ #:nodoc:

      def self.read(path)
        new(path).read
      end

      def initialize(path)
        @file = File.new(path)
        set_encoding
      rescue Errno::EACCES => e
        raise FileNotFoundException.new(e, File.expand_path(path))
      rescue Errno::ENOENT
        raise FeatureFolderNotFoundException, path
      end

      def read
        @file.read.encode('UTF-8')
      end

      private

      def set_encoding
        @file.each do |line|
          if ENCODING_PATTERN =~ line
            @file.set_encoding Regexp.last_match(1)
            break
          end
          break unless COMMENT_OR_EMPTY_LINE_PATTERN =~ line
        end
        @file.rewind
      end
    end

    require 'cucumber/formatter/ignore_missing_messages'
    require 'cucumber/formatter/fail_fast'
    require 'cucumber/formatter/publish_banner_printer'
    require 'cucumber/core/report/summary'

    def report
      return @report if @report
      reports = [summary_report] + formatters
      reports << fail_fast_report if @configuration.fail_fast?
      reports << publish_banner_printer unless @configuration.publish_quiet?
      @report ||= Formatter::Fanout.new(reports)
    end

    def summary_report
      @summary_report ||= Core::Report::Summary.new(@configuration.event_bus)
    end

    def fail_fast_report
      @fail_fast_report ||= Formatter::FailFast.new(@configuration)
    end

    def publish_banner_printer
      @publish_banner_printer ||= Formatter::PublishBannerPrinter.new(@configuration)
    end

    def formatters
      @formatters ||=
        @configuration.formatter_factories do |factory, formatter_options, path_or_io|
          create_formatter(factory, formatter_options, path_or_io)
        end
    end

    def create_formatter(factory, formatter_options, path_or_io)
      if accept_options?(factory)
        return factory.new(@configuration, formatter_options) if path_or_io.nil?
        factory.new(@configuration.with_options(out_stream: path_or_io),
                    formatter_options)
      else
        return factory.new(@configuration) if path_or_io.nil?
        factory.new(@configuration.with_options(out_stream: path_or_io))
      end
    end

    def accept_options?(factory)
      factory.instance_method(:initialize).arity > 1
    end

    def failure?
      if @configuration.wip?
        summary_report.test_cases.total_passed > 0
      else
        !summary_report.ok?(@configuration.strict)
      end
    end
    public :failure?

    require 'cucumber/core/test/filters'
    def filters # rubocop:disable Metrics/AbcSize
      tag_expressions = @configuration.tag_expressions
      name_regexps = @configuration.name_regexps
      tag_limits = @configuration.tag_limits
      [].tap do |filters|
        filters << Filters::TagLimits.new(tag_limits) if tag_limits.any?
        filters << Cucumber::Core::Test::TagFilter.new(tag_expressions)
        filters << Cucumber::Core::Test::NameFilter.new(name_regexps)
        filters << Cucumber::Core::Test::LocationsFilter.new(filespecs.locations)
        filters << Filters::Randomizer.new(@configuration.seed) if @configuration.randomize?
        # TODO: can we just use Glue::RegistryAndMore's step definitions directly?
        step_match_search = StepMatchSearch.new(@support_code.registry.method(:step_matches), @configuration)
        filters << Filters::ActivateSteps.new(step_match_search, @configuration)
        @configuration.filters.each { |filter| filters << filter }

        unless configuration.dry_run?
          filters << Filters::ApplyAfterStepHooks.new(@support_code)
          filters << Filters::ApplyBeforeHooks.new(@support_code)
          filters << Filters::ApplyAfterHooks.new(@support_code)
          filters << Filters::ApplyAroundHooks.new(@support_code)
        end

        filters << Filters::BroadcastTestCaseReadyEvent.new(@configuration)

        unless configuration.dry_run?
          filters << Filters::BroadcastTestRunStartedEvent.new(@configuration)
          filters << Filters::Quit.new
          filters << Filters::Retry.new(@configuration)
          # need to do this last so it becomes the first test step
          filters << Filters::PrepareWorld.new(self)
        end
      end
    end

    def load_step_definitions
      files = @configuration.support_to_load + @configuration.step_defs_to_load
      @support_code.load_files!(files)
    end

    def install_wire_plugin
      Cucumber::Wire::Plugin.new(@configuration, @support_code.registry).install if @configuration.all_files_to_load.any? { |f| f =~ /\.wire$/ }
    end

    def log
      Cucumber.logger
    end
  end
end
