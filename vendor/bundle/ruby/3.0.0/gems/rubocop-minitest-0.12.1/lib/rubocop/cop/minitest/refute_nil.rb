# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `refute_nil`
      # instead of using `refute_equal(nil, something)`.
      #
      # @example
      #   # bad
      #   refute_equal(nil, actual)
      #   refute_equal(nil, actual, 'message')
      #
      #   # good
      #   refute_nil(actual)
      #   refute_nil(actual, 'message')
      #
      class RefuteNil < Base
        include ArgumentRangeHelper
        extend AutoCorrector

        MSG = 'Prefer using `refute_nil(%<arguments>s)` over ' \
              '`refute_equal(nil, %<arguments>s)`.'
        RESTRICT_ON_SEND = %i[refute_equal].freeze

        def_node_matcher :refute_equal_with_nil, <<~PATTERN
          (send nil? :refute_equal nil $_ $...)
        PATTERN

        def on_send(node)
          refute_equal_with_nil(node) do |actual, message|
            message = message.first

            arguments = [actual.source, message&.source].compact.join(', ')

            add_offense(node, message: format(MSG, arguments: arguments)) do |corrector|
              corrector.replace(node.loc.selector, 'refute_nil')
              corrector.replace(
                first_and_second_arguments_range(node), actual.source
              )
            end
          end
        end
      end
    end
  end
end
