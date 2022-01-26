# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert(actual)`
      # instead of using `assert_equal(true, actual)`.
      #
      # @example
      #   # bad
      #   assert_equal(true, actual)
      #   assert_equal(true, actual, 'message')
      #
      #   # good
      #   assert(actual)
      #   assert(actual, 'message')
      #
      class AssertTruthy < Base
        include ArgumentRangeHelper
        extend AutoCorrector

        MSG = 'Prefer using `assert(%<arguments>s)` over ' \
              '`assert_equal(true, %<arguments>s)`.'
        RESTRICT_ON_SEND = %i[assert_equal].freeze

        def_node_matcher :assert_equal_with_truthy, <<~PATTERN
          (send nil? :assert_equal true $_ $...)
        PATTERN

        def on_send(node)
          assert_equal_with_truthy(node) do |actual, rest_receiver_arg|
            message = rest_receiver_arg.first

            arguments = [actual.source, message&.source].compact.join(', ')

            add_offense(node, message: format(MSG, arguments: arguments)) do |corrector|
              corrector.replace(node.loc.selector, 'assert')
              corrector.replace(first_and_second_arguments_range(node), actual.source)
            end
          end
        end
      end
    end
  end
end
