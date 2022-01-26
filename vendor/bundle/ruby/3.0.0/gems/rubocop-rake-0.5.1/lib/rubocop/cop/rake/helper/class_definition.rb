# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      module Helper
        module ClassDefinition
          extend NodePattern::Macros
          extend self

          def_node_matcher :class_definition?, <<~PATTERN
            {
              class module sclass
              (block
                (send (const {nil? cbase} {:Class :Module}) :new)
                args
                _
              )
            }
          PATTERN

          def in_class_definition?(node)
            node.each_ancestor(:class, :module, :sclass, :block).any? do |a|
              class_definition?(a)
            end
          end
        end
      end
    end
  end
end
