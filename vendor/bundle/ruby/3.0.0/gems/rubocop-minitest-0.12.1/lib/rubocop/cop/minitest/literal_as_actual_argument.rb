# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces correct order of expected and
      # actual arguments for `assert_equal`.
      #
      # @example
      #   # bad
      #   assert_equal foo, 2
      #   assert_equal foo, [1, 2]
      #   assert_equal foo, [1, 2], 'message'
      #
      #   # good
      #   assert_equal 2, foo
      #   assert_equal [1, 2], foo
      #   assert_equal [1, 2], foo, 'message'
      #
      class LiteralAsActualArgument < Base
        include ArgumentRangeHelper
        extend AutoCorrector

        MSG = 'Replace the literal with the first argument.'
        RESTRICT_ON_SEND = %i[assert_equal].freeze

        def on_send(node)
          return unless node.method?(:assert_equal)

          actual = node.arguments[1]
          return unless actual&.recursive_basic_literal?

          add_offense(all_arguments_range(node)) do |corrector|
            autocorrect(corrector, node)
          end
        end

        def autocorrect(corrector, node)
          expected, actual, message = *node.arguments

          new_actual_source = if actual.hash_type? && !actual.braces?
                                "{#{actual.source}}"
                              else
                                actual.source
                              end
          arguments = [new_actual_source, expected.source, message&.source].compact.join(', ')

          corrector.replace(node, "assert_equal(#{arguments})")
        end
      end
    end
  end
end
