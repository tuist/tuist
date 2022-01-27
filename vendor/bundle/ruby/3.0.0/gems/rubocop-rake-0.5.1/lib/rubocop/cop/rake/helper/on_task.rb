# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      module Helper
        module OnTask
          extend NodePattern::Macros

          def_node_matcher :task?, <<~PATTERN
            (send nil? :task ...)
          PATTERN

          def on_send(node)
            return unless task?(node)

            on_task(node)
          end
        end
      end
    end
  end
end
