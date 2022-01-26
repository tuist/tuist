# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks whether constant value isn't relative date.
      # Because the relative date will be evaluated only once.
      #
      # @example
      #   # bad
      #   class SomeClass
      #     EXPIRED_AT = 1.week.since
      #   end
      #
      #   # good
      #   class SomeClass
      #     EXPIRES = 1.week
      #
      #     def self.expired_at
      #       EXPIRES.since
      #     end
      #   end
      #
      #   # good
      #   class SomeClass
      #     def self.expired_at
      #       1.week.since
      #     end
      #   end
      class RelativeDateConstant < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Do not assign `%<method_name>s` to constants as it ' \
              'will be evaluated only once.'
        RELATIVE_DATE_METHODS = %i[since from_now after ago until before yesterday tomorrow].freeze

        def on_casgn(node)
          return if node.children[2]&.block_type?

          node.each_descendant(:send) do |send_node|
            relative_date?(send_node) do |method_name|
              add_offense(node, message: message(method_name)) do |corrector|
                autocorrect(corrector, node)
              end
            end
          end
        end

        def on_masgn(node)
          lhs, rhs = *node

          return unless rhs&.array_type?

          lhs.children.zip(rhs.children).each do |(name, value)|
            next unless name.casgn_type?

            relative_date?(value) do |method_name|
              add_offense(offense_range(name, value), message: message(method_name)) do |corrector|
                autocorrect(corrector, node)
              end
            end
          end
        end

        def on_or_asgn(node)
          relative_date_or_assignment?(node) do |method_name|
            add_offense(node, message: format(MSG, method_name: method_name))
          end
        end

        private

        def autocorrect(corrector, node)
          return unless node.casgn_type?

          scope, const_name, value = *node
          return unless scope.nil?

          indent = ' ' * node.loc.column
          new_code = ["def self.#{const_name.downcase}",
                      "#{indent}#{value.source}",
                      'end'].join("\n#{indent}")

          corrector.replace(node.source_range, new_code)
        end

        def message(method_name)
          format(MSG, method_name: method_name)
        end

        def offense_range(name, value)
          range_between(name.loc.expression.begin_pos, value.loc.expression.end_pos)
        end

        def relative_date_method?(method_name)
          RELATIVE_DATE_METHODS.include?(method_name)
        end

        def_node_matcher :relative_date_or_assignment?, <<~PATTERN
          (:or_asgn (casgn _ _) (send _ $#relative_date_method?))
        PATTERN

        def_node_matcher :relative_date?, <<~PATTERN
          {
            ({erange irange} _ (send _ $#relative_date_method?))
            ({erange irange} (send _ $#relative_date_method?) _)
            (send _ $#relative_date_method?)
          }
        PATTERN
      end
    end
  end
end
