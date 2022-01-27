# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_nil`
      # instead of using `assert_equal(nil, something)`.
      #
      # @example
      #   # bad
      #   assert_equal(nil, actual)
      #   assert_equal(nil, actual, 'message')
      #
      #   # good
      #   assert_nil(actual)
      #   assert_nil(actual, 'message')
      #
      class AssertNil < Base
        include ArgumentRangeHelper
        extend AutoCorrector

        MSG = 'Prefer using `assert_nil(%<arguments>s)` over ' \
              '`assert_equal(nil, %<arguments>s)`.'
        RESTRICT_ON_SEND = %i[assert_equal].freeze

        def_node_matcher :assert_equal_with_nil, <<~PATTERN
          (send nil? :assert_equal nil $_ $...)
        PATTERN

        def on_send(node)
          assert_equal_with_nil(node) do |actual, message|
            message = message.first

            arguments = [actual.source, message&.source].compact.join(', ')

            add_offense(node, message: format(MSG, arguments: arguments)) do |corrector|
              corrector.replace(node.loc.selector, 'assert_nil')
              corrector.replace(first_and_second_arguments_range(node), actual.source)
            end
          end
        end
      end
    end
  end
end
