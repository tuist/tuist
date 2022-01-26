# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      module Helper
        module TaskName
          extend self

          def task_name(node)
            first_arg = node.arguments[0]
            case first_arg&.type
            when :sym, :str
              first_arg.value.to_sym
            when :hash
              return nil if first_arg.children.size != 1

              pair = first_arg.children.first
              key = pair.children.first
              case key.type
              when :sym, :str
                key.value.to_sym
              end
            end
          end
        end
      end
    end
  end
end
