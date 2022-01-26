# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the use of `refute(object)`
      # over `assert_equal(false, object)`.
      #
      # @example
      #   # bad
      #   assert_equal(false, actual)
      #   assert_equal(false, actual, 'message')
      #
      #   assert(!test)
      #   assert(!test, 'message')
      #
      #   # good
      #   refute(actual)
      #   refute(actual, 'message')
      #
      class RefuteFalse < Base
        include ArgumentRangeHelper
        extend AutoCorrector

        MSG_FOR_ASSERT_EQUAL = 'Prefer using `refute(%<arguments>s)` over ' \
              '`assert_equal(false, %<arguments>s)`.'
        MSG_FOR_ASSERT = 'Prefer using `refute(%<arguments>s)` over ' \
              '`assert(!%<arguments>s)`.'
        RESTRICT_ON_SEND = %i[assert_equal assert].freeze

        def_node_matcher :assert_equal_with_false, <<~PATTERN
          (send nil? :assert_equal false $_ $...)
        PATTERN

        def_node_matcher :assert_with_bang_argument, <<~PATTERN
          (send nil? :assert (send $_ :!) $...)
        PATTERN

        def on_send(node)
          actual, rest_receiver_arg = assert_equal_with_false(node) || assert_with_bang_argument(node)
          return unless actual

          message_argument = rest_receiver_arg.first

          arguments = [actual.source, message_argument&.source].compact.join(', ')

          message = node.method?(:assert_equal) ? MSG_FOR_ASSERT_EQUAL : MSG_FOR_ASSERT

          add_offense(node, message: format(message, arguments: arguments)) do |corrector|
            autocorrect(corrector, node, actual)
          end
        end

        private

        def autocorrect(corrector, node, actual)
          corrector.replace(node.loc.selector, 'refute')

          if node.method?(:assert_equal)
            corrector.replace(first_and_second_arguments_range(node), actual.source)
          else
            corrector.replace(first_argument_range(node), actual.source)
          end
        end
      end
    end
  end
end
