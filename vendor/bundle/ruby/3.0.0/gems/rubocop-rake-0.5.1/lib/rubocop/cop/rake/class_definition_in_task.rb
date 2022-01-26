# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      # This cop detects class or module definition in a task or namespace,
      # because it is defined to the top level.
      # It is confusing because the scope looks in the task or namespace,
      # but actually it is defined to the top level.
      #
      # @example
      #   # bad
      #   task :foo do
      #     class C
      #     end
      #   end
      #
      #   # bad
      #   namespace :foo do
      #     module M
      #     end
      #   end
      #
      #   # good - It is also defined to the top level,
      #   #        but it looks expected behavior.
      #   class C
      #   end
      #   task :foo do
      #   end
      #
      class ClassDefinitionInTask < Cop
        MSG = 'Do not define a %<type>s in rake task, because it will be defined to the top level.'

        def on_class(node)
          return if Helper::ClassDefinition.in_class_definition?(node)
          return unless Helper::TaskDefinition.in_task_or_namespace?(node)

          add_offense(node)
        end

        def message(node)
          format(MSG, type: node.type)
        end

        alias on_module on_class
      end
    end
  end
end
