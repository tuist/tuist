# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop enforces the use of `pick` over `pluck(...).first`.
      #
      # Using `pluck` followed by `first` creates an intermediate array, which
      # `pick` avoids. When called on an Active Record relation, `pick` adds a
      # limit to the query so that only one value is fetched from the database.
      #
      # @example
      #   # bad
      #   Model.pluck(:a).first
      #   [{ a: :b, c: :d }].pluck(:a, :b).first
      #
      #   # good
      #   Model.pick(:a)
      #   [{ a: :b, c: :d }].pick(:a, :b)
      class Pick < Base
        extend AutoCorrector
        extend TargetRailsVersion

        MSG = 'Prefer `pick(%<args>s)` over `pluck(%<args>s).first`.'
        RESTRICT_ON_SEND = %i[first].freeze

        minimum_target_rails_version 6.0

        def_node_matcher :pick_candidate?, <<~PATTERN
          (send (send _ :pluck ...) :first)
        PATTERN

        def on_send(node)
          pick_candidate?(node) do
            receiver = node.receiver
            receiver_selector = receiver.loc.selector
            node_selector = node.loc.selector
            range = receiver_selector.join(node_selector)

            add_offense(range, message: message(receiver)) do |corrector|
              first_range = receiver.source_range.end.join(node_selector)

              corrector.remove(first_range)
              corrector.replace(receiver_selector, 'pick')
            end
          end
        end

        private

        def message(receiver)
          format(MSG, args: receiver.arguments.map(&:source).join(', '))
        end
      end
    end
  end
end
