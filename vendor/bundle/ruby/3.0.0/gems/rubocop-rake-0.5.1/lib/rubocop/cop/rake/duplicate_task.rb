# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      # If tasks are defined with the same name, Rake executes the both tasks
      # in definition order.
      # It is misleading sometimes. You should squash them into one definition.
      # This cop detects it.
      #
      # @example
      #   # bad
      #   task :foo do
      #     p 'foo 1'
      #   end
      #   task :foo do
      #     p 'foo 2'
      #   end
      #
      #   # good
      #   task :foo do
      #     p 'foo 1'
      #     p 'foo 2'
      #   end
      #
      class DuplicateTask < Cop
        include Helper::OnTask

        MSG = 'Task `%<task>s` is defined at both %<previous>s and %<current>s.'

        def initialize(*)
          super
          @tasks = {}
        end

        def on_task(node)
          namespaces = namespaces(node)
          return if namespaces.include?(nil)

          task_name = Helper::TaskName.task_name(node)
          return unless task_name

          full_name = [*namespaces.reverse, task_name].join(':')
          if (previous = @tasks[full_name])
            message = message_for_dup(previous: previous, current: node, task_name: full_name)
            add_offense(node, message: message)
          else
            @tasks[full_name] = node
          end
        end

        def namespaces(node)
          ns = []

          node.each_ancestor(:block) do |block_node|
            send_node = block_node.send_node
            next unless send_node.method_name == :namespace

            name = Helper::TaskName.task_name(send_node)
            ns << name
          end

          ns
        end

        def message_for_dup(previous:, current:, task_name:)
          format(
            MSG,
            task: task_name,
            previous: source_location(previous),
            current: source_location(current),
          )
        end

        def source_location(node)
          range = node.location.expression
          path = smart_path(range.source_buffer.name)
          "#{path}:#{range.line}"
        end
      end
    end
  end
end
