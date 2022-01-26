# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # In Ruby 2.7, `Enumerable#filter_map` has been added.
      #
      # This cop identifies places where `map { ... }.compact` can be replaced by `filter_map`.
      #
      # @safety
      #   This cop's autocorrection is unsafe because `map { ... }.compact` that is not
      #   compatible with `filter_map`.
      #
      # [source,ruby]
      # ----
      # [true, false, nil].compact              #=> [true, false]
      # [true, false, nil].filter_map(&:itself) #=> [true]
      # ----
      #
      # @example
      #   # bad
      #   ary.map(&:foo).compact
      #   ary.collect(&:foo).compact
      #
      #   # good
      #   ary.filter_map(&:foo)
      #   ary.map(&:foo).compact!
      #   ary.compact.map(&:foo)
      #
      class MapCompact < Base
        include RangeHelp
        extend AutoCorrector
        extend TargetRubyVersion

        MSG = 'Use `filter_map` instead.'
        RESTRICT_ON_SEND = %i[compact].freeze

        minimum_target_ruby_version 2.7

        def_node_matcher :map_compact, <<~PATTERN
          {
            (send
              $(send _ {:map :collect}
                (block_pass
                  (sym _))) _)
            (send
              (block
                $(send _ {:map :collect})
                  (args ...) _) _)
          }
        PATTERN

        def on_send(node)
          return unless (map_node = map_compact(node))

          compact_loc = node.loc
          range = range_between(map_node.loc.selector.begin_pos, compact_loc.selector.end_pos)

          add_offense(range) do |corrector|
            corrector.replace(map_node.loc.selector, 'filter_map')
            remove_compact_method(corrector, node, node.parent)
          end
        end

        private

        def remove_compact_method(corrector, compact_node, chained_method)
          compact_method_range = compact_node.loc.selector

          if compact_node.multiline? && chained_method&.loc.respond_to?(:selector) && chained_method.dot? &&
             !map_method_and_compact_method_on_same_line?(compact_node) &&
             !invoke_method_after_map_compact_on_same_line?(compact_node, chained_method)
            compact_method_range = compact_method_with_final_newline_range(compact_method_range)
          else
            corrector.remove(compact_node.loc.dot)
          end

          corrector.remove(compact_method_range)
        end

        def map_method_and_compact_method_on_same_line?(compact_node)
          return false unless compact_node.children.first.respond_to?(:send_node)

          map_node = compact_node.children.first.send_node

          compact_node.loc.selector.line == map_node.loc.selector.line
        end

        def invoke_method_after_map_compact_on_same_line?(compact_node, chained_method)
          compact_node.loc.selector.line == chained_method.loc.selector.line
        end

        def compact_method_with_final_newline_range(compact_method_range)
          range_by_whole_lines(compact_method_range, include_final_newline: true)
        end
      end
    end
  end
end
