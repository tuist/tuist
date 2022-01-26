# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop enforces the use of `collection.exclude?(obj)`
      # over `!collection.include?(obj)`.
      #
      # It is marked as unsafe by default because false positive will occur for
      # a receiver object that do not have `exclude?` method. (e.g. `IPAddr`)
      #
      # @example
      #   # bad
      #   !array.include?(2)
      #   !hash.include?(:key)
      #
      #   # good
      #   array.exclude?(2)
      #   hash.exclude?(:key)
      #
      class NegateInclude < Base
        extend AutoCorrector

        MSG = 'Use `.exclude?` and remove the negation part.'
        RESTRICT_ON_SEND = %i[!].freeze

        def_node_matcher :negate_include_call?, <<~PATTERN
          (send (send $_ :include? $_) :!)
        PATTERN

        def on_send(node)
          return unless (receiver, obj = negate_include_call?(node))

          add_offense(node) do |corrector|
            corrector.replace(node, "#{receiver.source}.exclude?(#{obj.source})")
          end
        end
      end
    end
  end
end
