# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks that `tag` is used instead of `content_tag`
      # because `content_tag` is legacy syntax.
      #
      # NOTE: Allow `content_tag` when the first argument is a variable because
      #      `content_tag(name)` is simpler rather than `tag.public_send(name)`.
      #
      # @example
      #  # bad
      #  content_tag(:p, 'Hello world!')
      #  content_tag(:br)
      #
      #  # good
      #  tag.p('Hello world!')
      #  tag.br
      #  content_tag(name, 'Hello world!')
      class ContentTag < Base
        include RangeHelp
        extend AutoCorrector
        extend TargetRailsVersion

        minimum_target_rails_version 5.1

        MSG = 'Use `tag` instead of `content_tag`.'
        RESTRICT_ON_SEND = %i[content_tag].freeze

        def on_new_investigation
          @corrected_nodes = nil
        end

        def on_send(node)
          first_argument = node.first_argument
          return if !first_argument ||
                    allowed_argument?(first_argument) ||
                    corrected_ancestor?(node)

          add_offense(node) do |corrector|
            autocorrect(corrector, node)

            @corrected_nodes ||= Set.new.compare_by_identity
            @corrected_nodes.add(node)
          end
        end

        private

        def corrected_ancestor?(node)
          node.each_ancestor(:send).any? { |ancestor| @corrected_nodes&.include?(ancestor) }
        end

        def allowed_argument?(argument)
          argument.variable? || argument.send_type? || argument.const_type? || argument.splat_type?
        end

        def autocorrect(corrector, node)
          if method_name?(node.first_argument)
            range = correction_range(node)

            rest_args = node.arguments.drop(1)
            replacement = "tag.#{node.first_argument.value.to_s.underscore}(#{rest_args.map(&:source).join(', ')})"

            corrector.replace(range, replacement)
          else
            corrector.replace(node.loc.selector, 'tag')
          end
        end

        def method_name?(node)
          return false unless node.str_type? || node.sym_type?

          /^[a-zA-Z_][a-zA-Z_\-0-9]*$/.match?(node.value)
        end

        def correction_range(node)
          range_between(node.loc.selector.begin_pos, node.loc.expression.end_pos)
        end
      end
    end
  end
end
