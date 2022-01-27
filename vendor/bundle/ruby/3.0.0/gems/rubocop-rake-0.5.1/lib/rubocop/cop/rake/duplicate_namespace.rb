# frozen_string_literal: true

module RuboCop
  module Cop
    module Rake
      # If namespaces are defined with the same name, Rake executes the both namespaces
      # in definition order.
      # It is redundant. You should squash them into one definition.
      # This cop detects it.
      #
      # @example
      #   # bad
      #   namespace :foo do
      #     task :bar do
      #     end
      #   end
      #   namespace :foo do
      #     task :hoge do
      #     end
      #   end
      #
      #   # good
      #   namespace :foo do
      #     task :bar do
      #     end
      #     task :hoge do
      #     end
      #   end
      #
      class DuplicateNamespace < Cop
        include Helper::OnNamespace

        MSG = 'Namespace `%<namespace>s` is defined at both %<previous>s and %<current>s.'

        def initialize(*)
          super
          @namespaces = {}
        end

        def on_namespace(node)
          namespaces = namespaces(node)
          return if namespaces.include?(nil)

          full_name = namespaces.reverse.join(':')
          if (previous = @namespaces[full_name])
            message = message_for_dup(previous: previous, current: node, namespace: full_name)
            add_offense(node, message: message)
          else
            @namespaces[full_name] = node
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

        def message_for_dup(previous:, current:, namespace:)
          format(
            MSG,
            namespace: namespace,
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
