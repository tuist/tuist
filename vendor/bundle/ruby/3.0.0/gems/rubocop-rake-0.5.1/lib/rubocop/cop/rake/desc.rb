# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      # Rake task definition should have a description with `desc` method.
      # It is useful as a documentation of task. And Rake does not display
      # task that does not have `desc` by `rake -T`.
      #
      # Note: This cop does not require description for the default task,
      #       because the default task is executed with `rake` without command.
      #
      # @example
      #   # bad
      #   task :do_something
      #
      #   # bad
      #   task :do_something do
      #   end
      #
      #   # good
      #   desc 'Do something'
      #   task :do_something
      #
      #   # good
      #   desc 'Do something'
      #   task :do_something do
      #   end
      #
      class Desc < Cop
        include Helper::OnTask

        MSG = 'Describe the task with `desc` method.'

        def on_task(node)
          return if task_with_desc?(node)
          return if Helper::TaskName.task_name(node) == :default

          add_offense(node)
        end

        private def task_with_desc?(node)
          parent, task = parent_and_task(node)
          return false unless parent
          return true unless can_insert_desc_to?(parent)

          idx = parent.children.find_index(task) - 1
          desc_candidate = parent.children[idx]
          return false unless desc_candidate

          desc_candidate.send_type? && desc_candidate.method_name == :desc
        end

        private def parent_and_task(task_node)
          parent = task_node.parent
          return nil, task_node unless parent
          return parent, task_node unless parent.block_type?

          if parent.children.find_index(task_node) == 0
            # when task {}
            [parent.parent, parent]
          else
            # when something { task }
            [parent, task_node]
          end
        end

        private def can_insert_desc_to?(parent)
          parent.begin_type? || parent.block_type? || parent.kwbegin_type?
        end
      end
    end
  end
end
