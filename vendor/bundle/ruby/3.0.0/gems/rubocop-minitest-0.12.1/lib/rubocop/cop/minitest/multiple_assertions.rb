# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop checks if test cases contain too many assertion calls.
      # The maximum allowed assertion calls is configurable.
      #
      # @example Max: 1
      #   # bad
      #   class FooTest < Minitest::Test
      #     def test_asserts_twice
      #       assert_equal(42, do_something)
      #       assert_empty(array)
      #     end
      #   end
      #
      #   # good
      #   class FooTest < Minitest::Test
      #     def test_asserts_once
      #       assert_equal(42, do_something)
      #     end
      #
      #     def test_another_asserts_once
      #       assert_empty(array)
      #     end
      #   end
      #
      class MultipleAssertions < Base
        include ConfigurableMax
        include MinitestExplorationHelpers

        MSG = 'Test case has too many assertions [%<total>d/%<max>d].'

        def on_class(class_node)
          return unless test_class?(class_node)

          test_cases(class_node).each do |node|
            assertions_count = assertions_count(node)

            next unless assertions_count > max_assertions

            self.max = assertions_count

            message = format(MSG, total: assertions_count, max: max_assertions)
            add_offense(node.loc.name, message: message)
          end
        end

        private

        def assertions_count(node)
          base = assertion?(node) ? 1 : 0
          base + node.each_child_node.sum { |c| assertions_count(c) }
        end

        def max_assertions
          Integer(cop_config.fetch('Max', 3))
        end
      end
    end
  end
end
