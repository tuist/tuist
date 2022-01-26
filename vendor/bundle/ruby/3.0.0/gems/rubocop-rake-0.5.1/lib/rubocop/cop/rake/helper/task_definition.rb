# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      module Helper
        module TaskDefinition
          extend NodePattern::Macros
          extend self

          def_node_matcher :task_or_namespace?, <<-PATTERN
            (block
              (send _ {:task :namespace} ...)
              args
              _
            )
          PATTERN

          def in_task_or_namespace?(node)
            node.each_ancestor(:block).any? do |a|
              task_or_namespace?(a)
            end
          end
        end
      end
    end
  end
end
