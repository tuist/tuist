# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop checks for a specified error in `assert_raises`.
      #
      # @example
      #   # bad
      #   assert_raises { raise FooException }
      #   assert_raises('This should have raised') { raise FooException }
      #
      #   # good
      #   assert_raises(FooException) { raise FooException }
      #   assert_raises(FooException, 'This should have raised') { raise FooException }
      #
      class UnspecifiedException < Base
        MSG = 'Specify the exception being captured.'

        def on_block(block_node)
          node = block_node.send_node
          return unless node.method?(:assert_raises)

          add_offense(node) if unspecified_exception?(node)
        end

        private

        def unspecified_exception?(node)
          args = node.arguments
          args.empty? || (args.size == 1 && args[0].str_type?)
        end
      end
    end
  end
end
