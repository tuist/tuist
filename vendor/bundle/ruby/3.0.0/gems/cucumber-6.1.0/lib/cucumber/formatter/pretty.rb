# frozen_string_literal: true

require 'fileutils'
require 'gherkin/dialect'
require 'cucumber/formatter/console'
require 'cucumber/formatter/io'
require 'cucumber/gherkin/formatter/escaping'
require 'cucumber/formatter/console_counts'
require 'cucumber/formatter/console_issues'
require 'cucumber/formatter/duration_extractor'
require 'cucumber/formatter/backtrace_filter'
require 'cucumber/formatter/ast_lookup'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format pretty</tt> (the default formatter).
    #
    # This formatter prints the result of the feature executions to plain text - exactly how they were parsed.
    #
    # If the output is STDOUT (and not a file), there are bright colours to watch too.
    #
    class Pretty # rubocop:disable Metrics/ClassLength
      include FileUtils
      include Console
      include Io
      include Cucumber::Gherkin::Formatter::Escaping
      attr_reader :config, :options
      private :config, :options
      attr_reader :current_feature_uri, :current_scenario_outline, :current_examples, :current_test_case
      private :current_feature_uri, :current_scenario_outline, :current_examples, :current_test_case
      attr_reader :in_scenario_outline, :print_background_steps
      private :in_scenario_outline, :print_background_steps

      def initialize(config)
        @io = ensure_io(config.out_stream, config.error_stream)
        @config = config
        @options = config.to_hash
        @snippets_input = []
        @undefined_parameter_types = []
        @total_duration = 0
        @exceptions = []
        @gherkin_sources = {}
        @step_matches = {}
        @ast_lookup = AstLookup.new(config)
        @counts = ConsoleCounts.new(config)
        @issues = ConsoleIssues.new(config, @ast_lookup)
        @first_feature = true
        @current_feature_uri = ''
        @current_scenario_outline = nil
        @current_examples = nil
        @current_test_case = nil
        @in_scenario_outline = false
        @print_background_steps = false
        @test_step_output = []
        @passed_test_cases = []
        @source_indent = 0
        @next_comment_to_be_printed = 0

        bind_events(config)
      end

      def bind_events(config)
        config.on_event :gherkin_source_read, &method(:on_gherkin_source_read)
        config.on_event :step_activated, &method(:on_step_activated)
        config.on_event :test_case_started, &method(:on_test_case_started)
        config.on_event :test_step_started, &method(:on_test_step_started)
        config.on_event :test_step_finished, &method(:on_test_step_finished)
        config.on_event :test_case_finished, &method(:on_test_case_finished)
        config.on_event :test_run_finished, &method(:on_test_run_finished)
        config.on_event :undefined_parameter_type, &method(:collect_undefined_parameter_type_names)
      end

      def on_gherkin_source_read(event)
        @gherkin_sources[event.path] = event.body
      end

      def on_step_activated(event)
        test_step, step_match = *event.attributes
        @step_matches[test_step.to_s] = step_match
      end

      def on_test_case_started(event)
        if !same_feature_as_previous_test_case?(event.test_case.location)
          if first_feature?
            @first_feature = false
            print_profile_information
          else
            print_comments(gherkin_source.split("\n").length, 0)
            @io.puts
          end
          @current_feature_uri = event.test_case.location.file
          @exceptions = []
          print_feature_data
          if feature_has_background?
            print_background_data
            @print_background_steps = true
            @in_scenario_outline = false
          end
        else
          @print_background_steps = false
        end
        @current_test_case = event.test_case
        print_step_header(current_test_case) unless print_background_steps
      end

      def on_test_step_started(event)
        return if event.test_step.hook?
        print_step_header(current_test_case) if first_step_after_printing_background_steps?(event.test_step)
      end

      def on_test_step_finished(event)
        collect_snippet_data(event.test_step, @ast_lookup) if event.result.undefined?
        return if in_scenario_outline && !options[:expand]
        exception_to_be_printed = find_exception_to_be_printed(event.result)
        print_step_data(event.test_step, event.result) if print_step_data?(event, exception_to_be_printed)
        print_step_output
        return unless exception_to_be_printed
        print_exception(exception_to_be_printed, event.result.to_sym, 6)
        @exceptions << exception_to_be_printed
      end

      def on_test_case_finished(event)
        @total_duration += DurationExtractor.new(event.result).result_duration
        @passed_test_cases << event.test_case if config.wip? && event.result.passed?
        if in_scenario_outline && !options[:expand]
          print_row_data(event.test_case, event.result)
        else
          exception_to_be_printed = find_exception_to_be_printed(event.result)
          return unless exception_to_be_printed
          print_exception(exception_to_be_printed, event.result.to_sym, 6)
          @exceptions << exception_to_be_printed
        end
      end

      def on_test_run_finished(_event)
        print_comments(gherkin_source.split("\n").length, 0) unless current_feature_uri.empty?
        @io.puts
        print_summary
      end

      def attach(src, media_type)
        return unless media_type == 'text/x.cucumber.log+plain'
        @test_step_output.push src
      end

      private

      def find_exception_to_be_printed(result)
        return nil if result.ok?(options[:strict])
        result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
        exception = result.failed? ? result.exception : result
        return nil if @exceptions.include?(exception)
        exception
      end

      def calculate_source_indent(test_case)
        scenario = scenario_source(test_case).scenario
        @source_indent = calculate_source_indent_for_ast_node(scenario)
      end

      def calculate_source_indent_for_ast_node(ast_node)
        indent = 4 + ast_node.keyword.length
        indent += 1 + ast_node.name.length
        ast_node.steps.each do |step|
          step_indent = 5 + step.keyword.length + step.text.length
          indent = step_indent if step_indent > indent
        end
        indent
      end

      def calculate_source_indent_for_expanded_test_case(test_case, scenario_keyword, expanded_name)
        indent = 7 + scenario_keyword.length
        indent += 2 + expanded_name.length
        test_case.test_steps.each do |step|
          if !step.hook? && step.location.lines.max >= test_case.location.lines.max
            step_indent = 9 + test_step_keyword(step).length + step.text.length
            indent = step_indent if step_indent > indent
          end
        end
        indent
      end

      def print_step_output
        @test_step_output.each { |message| @io.puts(format_string(message, :tag).indent(6)) }
        @test_step_output = []
      end

      def first_feature?
        @first_feature
      end

      def same_feature_as_previous_test_case?(location)
        location.file == current_feature_uri
      end

      def feature_has_background?
        feature_children = gherkin_document.feature.children
        return false if feature_children.empty?
        !feature_children.first.background.nil?
      end

      def print_step_header(test_case)
        if from_scenario_outline?(test_case)
          @in_scenario_outline = true
          unless same_outline_as_previous_test_case?(test_case)
            @current_scenario_outline = scenario_source(test_case).scenario_outline
            @io.puts
            print_outline_data(current_scenario_outline)
          end
          unless same_examples_as_previous_test_case?(test_case)
            @current_examples = scenario_source(test_case).examples
            @io.puts
            print_examples_data(current_examples)
          end
          print_expanded_row_data(current_test_case) if options[:expand]
        else
          @in_scenario_outline = false
          @current_scenario_outline = nil
          @current_examples = nil
          @io.puts
          @source_indent = calculate_source_indent(current_test_case)
          print_scenario_data(test_case)
        end
      end

      def same_outline_as_previous_test_case?(test_case)
        scenario_source(test_case).scenario_outline == current_scenario_outline
      end

      def same_examples_as_previous_test_case?(test_case)
        scenario_source(test_case).examples == current_examples
      end

      def from_scenario_outline?(test_case)
        scenario = scenario_source(test_case)
        scenario.type != :Scenario
      end

      def first_step_after_printing_background_steps?(test_step)
        return false unless print_background_steps
        return false unless test_step.location.lines.max >= current_test_case.location.lines.max
        @print_background_steps = false
        true
      end

      def print_feature_data
        feature = gherkin_document.feature
        print_language_comment(feature.location.line)
        print_comments(feature.location.line, 0)
        print_tags(feature.tags, 0)
        print_feature_line(feature)
        print_description(feature.description)
        @io.flush
      end

      def print_language_comment(feature_line)
        gherkin_source.split("\n")[0..feature_line].each do |line|
          @io.puts(format_string(line, :comment)) if /# *language *:/ =~ line
        end
      end

      def print_comments(up_to_line, indent)
        comments = gherkin_document.comments
        return if comments.empty? || comments.length <= @next_comment_to_be_printed
        comments[@next_comment_to_be_printed..-1].each do |comment|
          if comment.location.line <= up_to_line
            @io.puts(format_string(comment.text.strip, :comment).indent(indent))
            @next_comment_to_be_printed += 1
          end
          break if @next_comment_to_be_printed >= comments.length
        end
      end

      def print_tags(tags, indent)
        return if !tags || tags.empty?
        @io.puts(tags.map { |tag| format_string(tag.name, :tag) }.join(' ').indent(indent))
      end

      def print_feature_line(feature)
        print_keyword_name(feature.keyword, feature.name, 0)
      end

      def print_keyword_name(keyword, name, indent, location = nil)
        line = "#{keyword}:"
        line += " #{name}"
        @io.print(line.indent(indent))
        if location && options[:source]
          line_comment = format_string("# #{location}", :comment).indent(@source_indent - line.length - indent)
          @io.print(line_comment)
        end
        @io.puts
      end

      def print_description(description)
        return unless description
        description.split("\n").each do |line|
          @io.puts(line)
        end
      end

      def print_background_data
        @io.puts
        background = gherkin_document.feature.children.first.background
        @source_indent = calculate_source_indent_for_ast_node(background) if options[:source]
        print_comments(background.location.line, 2)
        print_background_line(background)
        print_description(background.description)
        @io.flush
      end

      def print_background_line(background)
        print_keyword_name(background.keyword, background.name, 2, "#{current_feature_uri}:#{background.location.line}")
      end

      def print_scenario_data(test_case)
        scenario = scenario_source(test_case).scenario
        print_comments(scenario.location.line, 2)
        print_tags(scenario.tags, 2)
        print_scenario_line(scenario, test_case.location)
        print_description(scenario.description)
        @io.flush
      end

      def print_scenario_line(scenario, location = nil)
        print_keyword_name(scenario.keyword, scenario.name, 2, location)
      end

      def print_step_data?(event, exception_to_be_printed)
        !event.test_step.hook? && (
          print_background_steps ||
          event.test_step.location.lines.max >= current_test_case.location.lines.max ||
          exception_to_be_printed
        )
      end

      def print_step_data(test_step, result)
        base_indent = options[:expand] && in_scenario_outline ? 8 : 4
        step_keyword = test_step_keyword(test_step)
        indent = options[:source] ? @source_indent - step_keyword.length - test_step.text.length - base_indent : nil
        print_comments(test_step.location.lines.max, base_indent)
        name_to_report = format_step(step_keyword, @step_matches.fetch(test_step.to_s) { NoStepMatch.new(test_step, test_step.text) }, result.to_sym, indent)
        @io.puts(name_to_report.indent(base_indent))
        print_multiline_argument(test_step, result, base_indent + 2) unless options[:no_multiline]
        @io.flush
      end

      def test_step_keyword(test_step)
        step = step_source(test_step).step
        step.keyword
      end

      def step_source(test_step)
        @ast_lookup.step_source(test_step)
      end

      def scenario_source(test_case)
        @ast_lookup.scenario_source(test_case)
      end

      def gherkin_source
        @gherkin_sources[current_feature_uri]
      end

      def gherkin_document
        @ast_lookup.gherkin_document(current_feature_uri)
      end

      def print_multiline_argument(test_step, result, indent)
        step = step_source(test_step).step
        if !step.doc_string.nil?
          print_doc_string(step.doc_string.content, result.to_sym, indent)
        elsif !step.data_table.nil?
          print_data_table(step.data_table, result.to_sym, indent)
        end
      end

      def print_data_table(data_table, status, indent)
        data_table.rows.each do |row|
          print_comments(row.location.line, indent)
          @io.puts format_string(gherkin_source.split("\n")[row.location.line - 1].strip, status).indent(indent)
        end
      end

      def print_outline_data(scenario_outline) # rubocop:disable Metrics/AbcSize
        print_comments(scenario_outline.location.line, 2)
        print_tags(scenario_outline.tags, 2)
        @source_indent = calculate_source_indent_for_ast_node(scenario_outline) if options[:source]
        print_scenario_line(scenario_outline, "#{current_feature_uri}:#{scenario_outline.location.line}")
        print_description(scenario_outline.description)
        scenario_outline.steps.each do |step|
          print_comments(step.location.line, 4)
          step_line = "    #{step.keyword}#{step.text}"
          @io.print(format_string(step_line, :skipped))
          if options[:source]
            comment_line = format_string("# #{current_feature_uri}:#{step.location.line}", :comment)
            @io.print(comment_line.indent(@source_indent - step_line.length))
          end
          @io.puts
          next if options[:no_multiline]
          print_doc_string(step.doc_string.content, :skipped, 6) unless step.doc_string.nil?
          print_data_table(step.data_table, :skipped, 6) unless step.data_table.nil?
        end
        @io.flush
      end

      def print_doc_string(content, status, indent)
        s = %("""\n#{content}\n""").indent(indent)
        s = s.split("\n").map { |l| l =~ /^\s+$/ ? '' : l }.join("\n")
        @io.puts(format_string(s, status))
      end

      def print_examples_data(examples)
        print_comments(examples.location.line, 4)
        print_tags(examples.tags, 4)
        print_keyword_name(examples.keyword, examples.name, 4)
        print_description(examples.description)
        unless options[:expand]
          print_comments(examples.table_header.location.line, 6)
          @io.puts(gherkin_source.split("\n")[examples.table_header.location.line - 1].strip.indent(6))
        end
        @io.flush
      end

      def print_row_data(test_case, result)
        print_comments(test_case.location.lines.max, 6)
        @io.print(format_string(gherkin_source.split("\n")[test_case.location.lines.max - 1].strip, result.to_sym).indent(6))
        @io.print(format_string(@test_step_output.join(', '), :tag).indent(2)) unless @test_step_output.empty?
        @test_step_output = []
        @io.puts
        if result.failed? || result.pending?
          result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
          exception = result.failed? ? result.exception : result
          unless @exceptions.include?(exception)
            print_exception(exception, result.to_sym, 6)
            @exceptions << exception
          end
        end
        @io.flush
      end

      def print_expanded_row_data(test_case)
        feature = gherkin_document.feature
        language_code = feature.language || 'en'
        language = ::Gherkin::Dialect.for(language_code)
        scenario_keyword = language.scenario_keywords[0]
        row = scenario_source(test_case).row
        expanded_name = '| ' + row.cells.map(&:value).join(' | ') + ' |'
        @source_indent = calculate_source_indent_for_expanded_test_case(test_case, scenario_keyword, expanded_name)
        @io.puts
        print_keyword_name(scenario_keyword, expanded_name, 6, test_case.location)
      end

      def print_summary
        print_statistics(@total_duration, config, @counts, @issues)
        print_snippets(options)
        print_passing_wip(config, @passed_test_cases, @ast_lookup)
      end
    end
  end
end
