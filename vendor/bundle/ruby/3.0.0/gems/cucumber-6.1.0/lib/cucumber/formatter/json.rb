# frozen_string_literal: true

require 'json'
require 'base64'
require 'cucumber/formatter/backtrace_filter'
require 'cucumber/formatter/io'
require 'cucumber/formatter/ast_lookup'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format json</tt>
    class Json
      include Io

      def initialize(config)
        @io = ensure_io(config.out_stream, config.error_stream)
        @ast_lookup = AstLookup.new(config)
        @feature_hashes = []
        @step_or_hook_hash = {}
        config.on_event :test_case_started, &method(:on_test_case_started)
        config.on_event :test_case_finished, &method(:on_test_case_finished)
        config.on_event :test_step_started, &method(:on_test_step_started)
        config.on_event :test_step_finished, &method(:on_test_step_finished)
        config.on_event :test_run_finished, &method(:on_test_run_finished)
      end

      def on_test_case_started(event)
        test_case = event.test_case
        builder = Builder.new(test_case, @ast_lookup)
        unless same_feature_as_previous_test_case?(test_case)
          @feature_hash = builder.feature_hash
          @feature_hashes << @feature_hash
        end
        @test_case_hash = builder.test_case_hash

        @element_hash = nil
        @element_background_hash = builder.background_hash
        @in_background = builder.background?

        @any_step_failed = false
      end

      def on_test_step_started(event)
        test_step = event.test_step
        return if internal_hook?(test_step)

        if @element_hash.nil?
          @element_hash = create_element_hash(test_step)
          feature_elements << @element_hash
        end

        if test_step.hook?
          @step_or_hook_hash = {}
          hooks_of_type(test_step) << @step_or_hook_hash
          return
        end
        if first_step_after_background?(test_step)
          @in_background = false
          feature_elements << @test_case_hash
          @element_hash = @test_case_hash
        end
        @step_or_hook_hash = create_step_hash(test_step)
        steps << @step_or_hook_hash
        @step_hash = @step_or_hook_hash
      end

      def on_test_step_finished(event)
        test_step, result = *event.attributes
        result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
        return if internal_hook?(test_step)
        add_match_and_result(test_step, result)
        @any_step_failed = true if result.failed?
      end

      def on_test_case_finished(event)
        feature_elements << @test_case_hash if @in_background

        _test_case, result = *event.attributes
        result = result.with_filtered_backtrace(Cucumber::Formatter::BacktraceFilter)
        add_failed_around_hook(result) if result.failed? && !@any_step_failed
      end

      def on_test_run_finished(_event)
        @io.write(JSON.generate(@feature_hashes, pretty: true))
      end

      def attach(src, mime_type)
        if mime_type == 'text/x.cucumber.log+plain'
          test_step_output << src
          return
        end
        if mime_type =~ /;base64$/
          mime_type = mime_type[0..-8]
          data = src
        else
          data = encode64(src)
        end
        test_step_embeddings << { mime_type: mime_type, data: data }
      end

      private

      def same_feature_as_previous_test_case?(test_case)
        current_feature[:uri] == test_case.location.file
      end

      def first_step_after_background?(test_step)
        @in_background && test_step.location.lines.max >= @test_case_hash[:line]
      end

      def internal_hook?(test_step)
        test_step.location.file.include?('lib/cucumber/')
      end

      def current_feature
        @feature_hash ||= {} # rubocop:disable Naming/MemoizedInstanceVariableName
      end

      def feature_elements
        @feature_hash[:elements] ||= []
      end

      def steps
        @element_hash[:steps] ||= []
      end

      def hooks_of_type(hook_step)
        case hook_step.text
        when 'Before hook'
          before_hooks
        when 'After hook'
          after_hooks
        when 'AfterStep hook'
          after_step_hooks
        else
          raise 'Unknown hook type ' + hook_step.to_s
        end
      end

      def before_hooks
        @element_hash[:before] ||= []
      end

      def after_hooks
        @element_hash[:after] ||= []
      end

      def around_hooks
        @element_hash[:around] ||= []
      end

      def after_step_hooks
        @step_hash[:after] ||= []
      end

      def test_step_output
        @step_or_hook_hash[:output] ||= []
      end

      def test_step_embeddings
        @step_or_hook_hash[:embeddings] ||= []
      end

      def create_element_hash(test_step)
        return @element_background_hash if @in_background && !first_step_after_background?(test_step)

        @in_background = false
        @test_case_hash
      end

      def create_step_hash(test_step)
        step_source = @ast_lookup.step_source(test_step).step
        step_hash = {
          keyword: step_source.keyword,
          name: test_step.text,
          line: test_step.location.lines.min
        }
        step_hash[:doc_string] = create_doc_string_hash(step_source.doc_string) unless step_source.doc_string.nil?
        step_hash[:rows] = create_data_table_value(step_source.data_table) unless step_source.data_table.nil?
        step_hash
      end

      def create_doc_string_hash(doc_string)
        content_type = doc_string.media_type || ''
        {
          value: doc_string.content,
          content_type: content_type,
          line: doc_string.location.line
        }
      end

      def create_data_table_value(data_table)
        data_table.rows.map do |row|
          { cells: row.cells.map(&:value) }
        end
      end

      def add_match_and_result(test_step, result)
        @step_or_hook_hash[:match] = create_match_hash(test_step, result)
        @step_or_hook_hash[:result] = create_result_hash(result)
        result.embeddings.each { |e| embed(e['src'], e['mime_type'], e['label']) } if result.respond_to?(:embeddings)
      end

      def add_failed_around_hook(result)
        @step_or_hook_hash = {}
        around_hooks << @step_or_hook_hash
        @step_or_hook_hash[:match] = { location: 'unknown_hook_location:1' }

        @step_or_hook_hash[:result] = create_result_hash(result)
      end

      def create_match_hash(test_step, _result)
        { location: test_step.action_location.to_s }
      end

      def create_result_hash(result)
        result_hash = {
          status: result.to_sym
        }
        result_hash[:error_message] = create_error_message(result) if result.failed? || result.pending?
        result.duration.tap { |duration| result_hash[:duration] = duration.nanoseconds }
        result_hash
      end

      def create_error_message(result)
        message_element = result.failed? ? result.exception : result
        message = "#{message_element.message} (#{message_element.class})"
        ([message] + message_element.backtrace).join("\n")
      end

      def encode64(data)
        # strip newlines from the encoded data
        Base64.encode64(data).delete("\n")
      end

      class Builder
        attr_reader :feature_hash, :background_hash, :test_case_hash

        def initialize(test_case, ast_lookup)
          @background_hash = nil
          uri = test_case.location.file
          feature = ast_lookup.gherkin_document(uri).feature
          feature(feature, uri)
          background(feature.children.first.background) unless feature.children.first.background.nil?
          scenario(ast_lookup.scenario_source(test_case), test_case)
        end

        def background?
          @background_hash != nil
        end

        def feature(feature, uri)
          @feature_hash = {
            id: create_id(feature.name),
            uri: uri,
            keyword: feature.keyword,
            name: feature.name,
            description: value_or_empty_string(feature.description),
            line: feature.location.line
          }
          return if feature.tags.empty?
          @feature_hash[:tags] = create_tags_array_from_hash_array(feature.tags)
        end

        def background(background)
          @background_hash = {
            keyword: background.keyword,
            name: background.name,
            description: value_or_empty_string(background.description),
            line: background.location.line,
            type: 'background',
            steps: []
          }
        end

        def scenario(scenario_source, test_case)
          scenario = scenario_source.type == :Scenario ? scenario_source.scenario : scenario_source.scenario_outline
          @test_case_hash = {
            id: "#{@feature_hash[:id]};#{create_id_from_scenario_source(scenario_source)}",
            keyword: scenario.keyword,
            name: test_case.name,
            description: value_or_empty_string(scenario.description),
            line: test_case.location.lines.max,
            type: 'scenario',
            steps: []
          }
          @test_case_hash[:tags] = create_tags_array_from_tags_array(test_case.tags) unless test_case.tags.empty?
        end

        private

        def value_or_empty_string(value)
          value.nil? ? '' : value
        end

        def create_id(name)
          name.downcase.tr(' ', '-')
        end

        def create_id_from_scenario_source(scenario_source)
          if scenario_source.type == :Scenario
            create_id(scenario_source.scenario.name)
          else
            scenario_outline_name = scenario_source.scenario_outline.name
            examples_name = scenario_source.examples.name
            row_number = calculate_row_number(scenario_source)
            "#{create_id(scenario_outline_name)};#{create_id(examples_name)};#{row_number}"
          end
        end

        def calculate_row_number(scenario_source)
          scenario_source.examples.table_body.each_with_index do |row, index|
            return index + 2 if row == scenario_source.row
          end
        end

        def create_tags_array_from_hash_array(tags)
          tags_array = []
          tags.each { |tag| tags_array << { name: tag.name, line: tag.location.line } }
          tags_array
        end

        def create_tags_array_from_tags_array(tags)
          tags_array = []
          tags.each { |tag| tags_array << { name: tag.name, line: tag.location.line } }
          tags_array
        end
      end
    end
  end
end
