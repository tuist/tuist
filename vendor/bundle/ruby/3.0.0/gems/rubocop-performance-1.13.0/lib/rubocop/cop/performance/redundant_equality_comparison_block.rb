# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop checks for uses `Enumerable#all?`, `Enumerable#any?`, `Enumerable#one?`,
      # and `Enumerable#none?` are compared with `===` or similar methods in block.
      #
      # By default, `Object#===` behaves the same as `Object#==`, but this
      # behavior is appropriately overridden in subclass. For example,
      # `Range#===` returns `true` when argument is within the range.
      #
      # @safety
      #   This cop is unsafe because `===` and `==` do not always behave the same.
      #
      # @example
      #   # bad
      #   items.all? { |item| pattern === item }
      #   items.all? { |item| item == other }
      #   items.all? { |item| item.is_a?(Klass) }
      #   items.all? { |item| item.kind_of?(Klass) }
      #
      #   # good
      #   items.all?(pattern)
      #
      class RedundantEqualityComparisonBlock < Base
        extend AutoCorrector

        MSG = 'Use `%<prefer>s` instead of block.'

        TARGET_METHODS = %i[all? any? one? none?].freeze
        COMPARISON_METHODS = %i[== === is_a? kind_of?].freeze
        IS_A_METHODS = %i[is_a? kind_of?].freeze

        def on_block(node)
          return unless TARGET_METHODS.include?(node.method_name)
          return unless one_block_argument?(node.arguments)

          block_argument = node.arguments.first
          block_body = node.body
          return unless use_equality_comparison_block?(block_body)
          return if same_block_argument_and_is_a_argument?(block_body, block_argument)
          return unless (new_argument = new_argument(block_argument, block_body))

          range = offense_range(node)
          prefer = "#{node.method_name}(#{new_argument})"

          add_offense(range, message: format(MSG, prefer: prefer)) do |corrector|
            corrector.replace(range, prefer)
          end
        end

        private

        def one_block_argument?(block_arguments)
          block_arguments.one? && !block_arguments.source.include?(',')
        end

        def use_equality_comparison_block?(block_body)
          block_body.send_type? && COMPARISON_METHODS.include?(block_body.method_name)
        end

        def same_block_argument_and_is_a_argument?(block_body, block_argument)
          if block_body.method?(:===)
            block_argument.source != block_body.children[2].source
          elsif IS_A_METHODS.include?(block_body.method_name)
            block_argument.source == block_body.first_argument.source
          else
            false
          end
        end

        def new_argument(block_argument, block_body)
          if block_argument.source == block_body.receiver.source
            rhs = block_body.first_argument
            return if use_block_argument_in_method_argument_of_operand?(block_argument, rhs)

            rhs.source
          elsif block_argument.source == block_body.first_argument.source
            lhs = block_body.receiver
            return if use_block_argument_in_method_argument_of_operand?(block_argument, lhs)

            lhs.source
          end
        end

        def use_block_argument_in_method_argument_of_operand?(block_argument, operand)
          return false unless operand.send_type?

          arguments = operand.arguments
          arguments.inject(arguments.map(&:source)) do |operand_sources, argument|
            operand_sources + argument.each_descendant(:lvar).map(&:source)
          end.any?(block_argument.source)
        end

        def offense_range(node)
          node.send_node.loc.selector.join(node.source_range.end)
        end
      end
    end
  end
end
