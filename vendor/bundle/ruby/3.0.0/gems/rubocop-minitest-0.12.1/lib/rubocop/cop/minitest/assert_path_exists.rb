# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_path_exists`
      # instead of using `assert(File.exist?(path))`.
      #
      # @example
      #   # bad
      #   assert(File.exist?(path))
      #   assert(File.exist?(path), 'message')
      #
      #   # good
      #   assert_path_exists(path)
      #   assert_path_exists(path, 'message')
      #
      class AssertPathExists < Base
        extend AutoCorrector

        MSG = 'Prefer using `%<good_method>s` over `%<bad_method>s`.'
        RESTRICT_ON_SEND = %i[assert].freeze

        def_node_matcher :assert_file_exists, <<~PATTERN
          (send nil? :assert
            (send
              (const _ :File) {:exist? :exists?} $_)
              $...)
        PATTERN

        def on_send(node)
          assert_file_exists(node) do |path, failure_message|
            failure_message = failure_message.first
            good_method = build_good_method(path, failure_message)
            message = format(MSG, good_method: good_method, bad_method: node.source)

            add_offense(node, message: message) do |corrector|
              corrector.replace(node, good_method)
            end
          end
        end

        private

        def build_good_method(path, message)
          args = [path.source, message&.source].compact.join(', ')
          "assert_path_exists(#{args})"
        end
      end
    end
  end
end
