# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      module Helper
        module OnNamespace
          extend NodePattern::Macros

          def_node_matcher :namespace?, <<~PATTERN
            (send nil? :namespace ...)
          PATTERN

          def on_send(node)
            return unless namespace?(node)

            on_namespace(node)
          end
        end
      end
    end
  end
end
