# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # Checks if collection can be blank-compacted with `compact_blank`.
      #
      # @safety
      #   It is unsafe by default because false positives may occur in the
      #   blank check of block arguments to the receiver object.
      #
      #   For example, `[[1, 2], [3, nil]].reject { |first, second| second.blank? }` and
      #   `[[1, 2], [3, nil]].compact_blank` are not compatible. The same is true for `blank?`.
      #   This will work fine when the receiver is a hash object.
      #
      # @example
      #
      #   # bad
      #   collection.reject(&:blank?)
      #   collection.reject { |_k, v| v.blank? }
      #
      #   # good
      #   collection.compact_blank
      #
      #   # bad
      #   collection.reject!(&:blank?)
      #   collection.reject! { |_k, v| v.blank? }
      #
      #   # good
      #   collection.compact_blank!
      #
      class CompactBlank < Base
        include RangeHelp
        extend AutoCorrector
        extend TargetRailsVersion

        MSG = 'Use `%<preferred_method>s` instead.'
        RESTRICT_ON_SEND = %i[reject reject!].freeze

        minimum_target_rails_version 6.1

        def_node_matcher :reject_with_block?, <<~PATTERN
          (block
            (send _ {:reject :reject!})
            $(args ...)
            (send
              $(lvar _) :blank?))
        PATTERN

        def_node_matcher :reject_with_block_pass?, <<~PATTERN
          (send _ {:reject :reject!}
            (block_pass
              (sym :blank?)))
        PATTERN

        def on_send(node)
          return unless bad_method?(node)

          range = offense_range(node)
          preferred_method = preferred_method(node)
          add_offense(range, message: format(MSG, preferred_method: preferred_method)) do |corrector|
            corrector.replace(range, preferred_method)
          end
        end

        private

        def bad_method?(node)
          return true if reject_with_block_pass?(node)

          if (arguments, receiver_in_block = reject_with_block?(node.parent))
            return use_single_value_block_argument?(arguments, receiver_in_block) ||
                   use_hash_value_block_argument?(arguments, receiver_in_block)
          end

          false
        end

        def use_single_value_block_argument?(arguments, receiver_in_block)
          arguments.length == 1 && arguments[0].source == receiver_in_block.source
        end

        def use_hash_value_block_argument?(arguments, receiver_in_block)
          arguments.length == 2 && arguments[1].source == receiver_in_block.source
        end

        def offense_range(node)
          end_pos = node.parent&.block_type? ? node.parent.loc.expression.end_pos : node.loc.expression.end_pos

          range_between(node.loc.selector.begin_pos, end_pos)
        end

        def preferred_method(node)
          node.method?(:reject) ? 'compact_blank' : 'compact_blank!'
        end
      end
    end
  end
end
