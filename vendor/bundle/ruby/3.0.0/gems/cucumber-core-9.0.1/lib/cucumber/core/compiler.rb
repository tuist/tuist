# frozen_string_literal: true

require 'cucumber/core/test/case'
require 'cucumber/core/test/step'
require 'cucumber/core/test/tag'
require 'cucumber/core/test/doc_string'
require 'cucumber/core/test/data_table'
require 'cucumber/core/test/empty_multiline_argument'
require 'cucumber/messages'

module Cucumber
  module Core
    # Compiles the Pickles into test cases
    class Compiler
      attr_reader :receiver, :gherkin_query, :id_generator
      private     :receiver, :gherkin_query, :id_generator

      def initialize(receiver, gherkin_query, event_bus = nil)
        @receiver = receiver
        @id_generator = Cucumber::Messages::IdGenerator::UUID.new
        @gherkin_query = gherkin_query
        @event_bus = event_bus
      end

      def pickle(pickle)
        test_case = create_test_case(pickle)
        test_case.describe_to(receiver)
      end

      def done
        receiver.done
        self
      end

      private

      def create_test_case(pickle)
        uri = pickle.uri
        test_steps = pickle.steps.map { |step| create_test_step(step, uri) }
        lines = source_lines_for_pickle(pickle).sort.reverse
        tags = pickle.tags.map { |tag| Test::Tag.new(Test::Location.new(uri, source_line_for_pickle_tag(tag)), tag.name) }
        test_case = Test::Case.new(id_generator.new_id, pickle.name, test_steps, Test::Location.new(uri, lines), tags, pickle.language)
        @event_bus&.test_case_created(test_case, pickle)
        test_case
      end

      def create_test_step(pickle_step, uri)
        lines = source_lines_for_pickle_step(pickle_step).sort.reverse
        multiline_arg = create_multiline_arg(pickle_step, uri)
        step = Test::Step.new(id_generator.new_id, pickle_step.text, Test::Location.new(uri, lines), multiline_arg)
        @event_bus&.test_step_created(step, pickle_step)
        step
      end

      def create_multiline_arg(pickle_step, _uri)
        if pickle_step.argument
          if pickle_step.argument.doc_string
            doc_string = pickle_step.argument.doc_string
            Test::DocString.new(
              doc_string.content,
              doc_string.media_type
            )
          elsif pickle_step.argument.data_table
            data_table = pickle_step.argument.data_table
            Test::DataTable.new(
              data_table.rows.map { |row| row.cells.map { |cell| cell.value } }
            )
          end
        else
          Test::EmptyMultilineArgument.new
        end
      end

      def source_lines_for_pickle(pickle)
        pickle.ast_node_ids.map { |id| source_line(id) }
      end

      def source_lines_for_pickle_step(pickle_step)
        pickle_step.ast_node_ids.map { |id| source_line(id) }
      end

      def source_line_for_pickle_tag(tag)
        source_line(tag.ast_node_id)
      end

      def source_line(id)
        gherkin_query.location(id).line
      end
    end
  end
end
