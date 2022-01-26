# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies places where `reverse.first(n)` and `reverse.first`
      # can be replaced by `last(n).reverse` and `last`.
      #
      # @example
      #
      #   # bad
      #   array.reverse.first(5)
      #   array.reverse.first
      #
      #   # good
      #   array.last(5).reverse
      #   array.last
      #
      class ReverseFirst < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Use `%<good_method>s` instead of `%<bad_method>s`.'
        RESTRICT_ON_SEND = %i[first].freeze

        def_node_matcher :reverse_first_candidate?, <<~PATTERN
          (send $(send _ :reverse) :first (int _)?)
        PATTERN

        def on_send(node)
          reverse_first_candidate?(node) do |receiver|
            range = correction_range(receiver, node)
            message = build_message(node)

            add_offense(range, message: message) do |corrector|
              replacement = build_good_method(node)

              corrector.replace(range, replacement)
            end
          end
        end

        private

        def correction_range(receiver, node)
          range_between(receiver.loc.selector.begin_pos, node.loc.expression.end_pos)
        end

        def build_message(node)
          good_method = build_good_method(node)
          bad_method = build_bad_method(node)
          format(MSG, good_method: good_method, bad_method: bad_method)
        end

        def build_good_method(node)
          if node.arguments?
            "last(#{node.arguments.first.source}).reverse"
          else
            'last'
          end
        end

        def build_bad_method(node)
          if node.arguments?
            "reverse.first(#{node.arguments.first.source})"
          else
            'reverse.first'
          end
        end
      end
    end
  end
end
