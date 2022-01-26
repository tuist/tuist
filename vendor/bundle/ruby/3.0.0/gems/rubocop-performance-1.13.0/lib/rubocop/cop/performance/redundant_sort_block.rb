# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies places where `sort { |a, b| a <=> b }`
      # can be replaced with `sort`.
      #
      # @example
      #   # bad
      #   array.sort { |a, b| a <=> b }
      #
      #   # good
      #   array.sort
      #
      class RedundantSortBlock < Base
        include SortBlock
        extend AutoCorrector

        MSG = 'Use `sort` instead of `%<bad_method>s`.'

        def on_block(node)
          return unless (send, var_a, var_b, body = sort_with_block?(node))

          replaceable_body?(body, var_a, var_b) do
            range = sort_range(send, node)

            add_offense(range, message: message(var_a, var_b)) do |corrector|
              corrector.replace(range, 'sort')
            end
          end
        end

        private

        def message(var_a, var_b)
          bad_method = "sort { |#{var_a}, #{var_b}| #{var_a} <=> #{var_b} }"
          format(MSG, bad_method: bad_method)
        end
      end
    end
  end
end
