# frozen_string_literal: true

module RuboCop
  module Cop
    # Methods that calculate and return `Parser::Source::Ranges`.
    module ArgumentRangeHelper
      include RangeHelp

      private

      def first_argument_range(node)
        first_argument = node.first_argument

        range_between(
          first_argument.source_range.begin_pos,
          first_argument.source_range.end_pos
        )
      end

      def first_and_second_arguments_range(node)
        first_argument = node.first_argument
        second_argument = node.arguments[1]

        range_between(
          first_argument.source_range.begin_pos,
          second_argument.source_range.end_pos
        )
      end

      def all_arguments_range(node)
        first_argument = node.first_argument
        last_argument = node.arguments.last

        range_between(
          first_argument.source_range.begin_pos,
          last_argument.source_range.end_pos
        )
      end
    end
  end
end
