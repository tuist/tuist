# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies places where numeric argument to BigDecimal should be
      # converted to string. Initializing from String is faster
      # than from Numeric for BigDecimal.
      #
      # @example
      #   # bad
      #   BigDecimal(1, 2)
      #   BigDecimal(1.2, 3, exception: true)
      #
      #   # good
      #   BigDecimal('1', 2)
      #   BigDecimal('1.2', 3, exception: true)
      #
      class BigDecimalWithNumericArgument < Base
        extend AutoCorrector

        MSG = 'Convert numeric argument to string before passing to `BigDecimal`.'
        RESTRICT_ON_SEND = %i[BigDecimal].freeze

        def_node_matcher :big_decimal_with_numeric_argument?, <<~PATTERN
          (send nil? :BigDecimal $numeric_type? ...)
        PATTERN

        def on_send(node)
          return unless (numeric = big_decimal_with_numeric_argument?(node))
          return if numeric.float_type? && specifies_precision?(node)

          add_offense(numeric.source_range) do |corrector|
            corrector.wrap(numeric, "'", "'")
          end
        end

        private

        def specifies_precision?(node)
          node.arguments.size > 1 && !node.arguments[1].hash_type?
        end
      end
    end
  end
end
