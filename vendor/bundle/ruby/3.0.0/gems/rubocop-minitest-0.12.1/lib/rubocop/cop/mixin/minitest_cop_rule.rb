# frozen_string_literal: true

module RuboCop
  module Cop
    # Provide a method to define offense rule for Minitest cops.
    module MinitestCopRule
      #
      # Define offense rule for Minitest cops.
      #
      # @example
      #   define_rule :assert, target_method: :match
      #   define_rule :refute, target_method: :match
      #   define_rule :assert, target_method: :include?, preferred_method: :assert_includes
      #   define_rule :assert, target_method: :instance_of?, inverse: true
      #
      # @param assertion_method [Symbol] Assertion method like `assert` or `refute`.
      # @param target_method [Symbol] Method name offensed by assertion method arguments.
      # @param preferred_method [Symbol] An optional param. Custom method name replaced by
      #                                  auto-correction. The preferred method name that connects
      #                                  `assertion_method` and `target_method` with `_` is
      #                                  the default name.
      # @param inverse [Boolean] An optional param. Order of arguments replaced by auto-correction.
      #
      def define_rule(assertion_method, target_method:, preferred_method: nil, inverse: false)
        preferred_method = "#{assertion_method}_#{target_method.to_s.delete('?')}" if preferred_method.nil?

        class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          include ArgumentRangeHelper
          extend AutoCorrector

          MSG = 'Prefer using `#{preferred_method}(%<new_arguments>s)` over ' \
                '`#{assertion_method}(%<original_arguments>s)`.'
          RESTRICT_ON_SEND = %i[#{assertion_method}].freeze

          def on_send(node)
            return unless node.method?(:#{assertion_method})
            return unless (arguments = peel_redundant_parentheses_from(node.arguments))
            return unless arguments.first.respond_to?(:method?) && arguments.first.method?(:#{target_method})

            add_offense(node, message: offense_message(arguments)) do |corrector|
              autocorrect(corrector, node, arguments)
            end
          end

          def autocorrect(corrector, node, arguments)
            corrector.replace(node.loc.selector, '#{preferred_method}')

            new_arguments = new_arguments(arguments).join(', ')

            if enclosed_in_redundant_parentheses?(node)
              new_arguments = '(' + new_arguments + ')'
            end

            corrector.replace(first_argument_range(node), new_arguments)
          end

          private

          def peel_redundant_parentheses_from(arguments)
            return arguments unless arguments.first&.begin_type?

            peel_redundant_parentheses_from(arguments.first.children)
          end

          def offense_message(arguments)
            message_argument = arguments.last if arguments.first != arguments.last

            new_arguments = [
              new_arguments(arguments),
              message_argument&.source
            ].flatten.compact.join(', ')

            original_arguments = arguments.map(&:source).join(', ')

            format(
              MSG,
              new_arguments: new_arguments,
              original_arguments: original_arguments
            )
          end

          def new_arguments(arguments)
            receiver = correct_receiver(arguments.first.receiver)
            method_argument = arguments.first.arguments.first&.source

            new_arguments = [receiver, method_argument].compact
            new_arguments.reverse! if #{inverse}
            new_arguments
          end

          def enclosed_in_redundant_parentheses?(node)
            node.arguments.first.begin_type?
          end

          def correct_receiver(receiver)
            receiver ? receiver.source : 'self'
          end
        RUBY
      end
    end
  end
end
