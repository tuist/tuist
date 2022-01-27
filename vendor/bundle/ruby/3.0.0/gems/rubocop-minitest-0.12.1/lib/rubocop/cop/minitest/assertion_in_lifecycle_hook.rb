# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop checks for usage of assertions in lifecycle hooks.
      #
      # @example
      #   # bad
      #   class FooTest < Minitest::Test
      #     def setup
      #       assert_equal(foo, bar)
      #     end
      #   end
      #
      #   # good
      #   class FooTest < Minitest::Test
      #     def test_something
      #       assert_equal(foo, bar)
      #     end
      #   end
      #
      class AssertionInLifecycleHook < Base
        include MinitestExplorationHelpers

        MSG = 'Do not use `%<assertion>s` in `%<hook>s` hook.'

        def on_class(class_node)
          return unless test_class?(class_node)

          lifecycle_hooks(class_node).each do |hook_node|
            hook_node.each_descendant(:send) do |node|
              if assertion?(node)
                message = format(MSG, assertion: node.method_name, hook: hook_node.method_name)
                add_offense(node, message: message)
              end
            end
          end
        end
      end
    end
  end
end
