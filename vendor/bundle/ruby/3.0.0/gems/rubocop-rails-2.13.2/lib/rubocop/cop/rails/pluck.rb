# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop enforces the use of `pluck` over `map`.
      #
      # `pluck` can be used instead of `map` to extract a single key from each
      # element in an enumerable. When called on an Active Record relation, it
      # results in a more efficient query that only selects the necessary key.
      #
      # @example
      #   # bad
      #   Post.published.map { |post| post[:title] }
      #   [{ a: :b, c: :d }].collect { |el| el[:a] }
      #
      #   # good
      #   Post.published.pluck(:title)
      #   [{ a: :b, c: :d }].pluck(:a)
      class Pluck < Base
        extend AutoCorrector
        extend TargetRailsVersion

        MSG = 'Prefer `pluck(:%<value>s)` over `%<method>s { |%<argument>s| %<element>s[:%<value>s] }`.'

        minimum_target_rails_version 5.0

        def_node_matcher :pluck_candidate?, <<~PATTERN
          (block (send _ ${:map :collect}) (args (arg $_argument)) (send (lvar $_element) :[] (sym $_value)))
        PATTERN

        def on_block(node)
          pluck_candidate?(node) do |method, argument, element, value|
            next unless argument == element

            message = message(method, argument, element, value)

            add_offense(offense_range(node), message: message) do |corrector|
              corrector.replace(offense_range(node), "pluck(:#{value})")
            end
          end
        end

        private

        def offense_range(node)
          node.send_node.loc.selector.join(node.loc.end)
        end

        def message(method, argument, element, value)
          format(MSG, method: method, argument: argument, element: element, value: value)
        end
      end
    end
  end
end
