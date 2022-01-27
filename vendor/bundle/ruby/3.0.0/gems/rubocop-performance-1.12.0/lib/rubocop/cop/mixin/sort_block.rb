# frozen_string_literal: true

module RuboCop
  module Cop
    # Common functionality for cops checking `Enumerable#sort` blocks.
    module SortBlock
      extend NodePattern::Macros
      include RangeHelp

      def_node_matcher :sort_with_block?, <<~PATTERN
        (block
          $(send _ :sort)
          (args (arg $_a) (arg $_b))
          $send)
      PATTERN

      def_node_matcher :replaceable_body?, <<~PATTERN
        (send (lvar %1) :<=> (lvar %2))
      PATTERN

      private

      def sort_range(send, node)
        range_between(send.loc.selector.begin_pos, node.loc.end.end_pos)
      end
    end
  end
end
