# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `refute_path_exists`
      # instead of using `refute(File.exist?(path))`.
      #
      # @example
      #   # bad
      #   refute(File.exist?(path))
      #   refute(File.exist?(path), 'message')
      #
      #   # good
      #   refute_path_exists(path)
      #   refute_path_exists(path, 'message')
      #
      class RefutePathExists < Base
        extend AutoCorrector

        MSG = 'Prefer using `%<good_method>s` over `%<bad_method>s`.'
        RESTRICT_ON_SEND = %i[refute].freeze

        def_node_matcher :refute_file_exists, <<~PATTERN
          (send nil? :refute
            (send
              (const _ :File) {:exist? :exists?} $_)
              $...)
        PATTERN

        def on_send(node)
          refute_file_exists(node) do |path, failure_message|
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
          "refute_path_exists(#{args})"
        end
      end
    end
  end
end
