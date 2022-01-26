# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces that test method names start with `test_` prefix.
      # It aims to prevent tests that aren't executed by forgetting to start test method name with `test_`.
      #
      # @example
      #   # bad
      #   class FooTest < Minitest::Test
      #     def does_something
      #       assert_equal 42, do_something
      #     end
      #   end
      #
      #   # good
      #   class FooTest < Minitest::Test
      #     def test_does_something
      #       assert_equal 42, do_something
      #     end
      #   end
      #
      #   # good
      #   class FooTest < Minitest::Test
      #     def helper_method(argument)
      #     end
      #   end
      #
      class TestMethodName < Base
        include MinitestExplorationHelpers
        include DefNode
        extend AutoCorrector

        MSG = 'Test method name should start with `test_` prefix.'

        def on_class(class_node)
          return unless test_class?(class_node)

          class_elements(class_node).each do |node|
            next unless offense?(node)

            test_method_name = node.loc.name

            add_offense(test_method_name) do |corrector|
              corrector.replace(test_method_name, "test_#{node.method_name}")
            end
          end
        end

        private

        def class_elements(class_node)
          class_def = class_node.body
          return [] unless class_def

          if class_def.def_type?
            [class_def]
          else
            class_def.each_child_node(:def).to_a
          end
        end

        def offense?(node)
          return false if assertions(node).none?

          public?(node) && node.arguments.empty? && !test_method_name?(node) && !lifecycle_hook_method?(node)
        end

        def public?(node)
          !non_public?(node)
        end

        def test_method_name?(node)
          node.method_name.to_s.start_with?('test_')
        end
      end
    end
  end
end
