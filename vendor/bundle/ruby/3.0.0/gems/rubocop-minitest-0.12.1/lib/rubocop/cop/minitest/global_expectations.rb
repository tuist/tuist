# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop checks for deprecated global expectations
      # and autocorrects them to use expect format.
      #
      # @example
      #   # bad
      #   musts.must_equal expected_musts
      #   wonts.wont_match expected_wonts
      #   musts.must_raise TypeError
      #
      #   # good
      #   _(musts).must_equal expected_musts
      #   _(wonts).wont_match expected_wonts
      #   _ { musts }.must_raise TypeError
      class GlobalExpectations < Base
        extend AutoCorrector

        MSG = 'Use `%<preferred>s` instead.'

        VALUE_MATCHERS = %i[
          must_be_empty must_equal must_be_close_to must_be_within_delta
          must_be_within_epsilon must_include must_be_instance_of must_be_kind_of
          must_match must_be_nil must_be must_respond_to must_be_same_as
          path_must_exist path_wont_exist wont_be_empty wont_equal wont_be_close_to
          wont_be_within_delta wont_be_within_epsilon wont_include wont_be_instance_of
          wont_be_kind_of wont_match wont_be_nil wont_be wont_respond_to wont_be_same_as
        ].freeze

        BLOCK_MATCHERS = %i[must_output must_raise must_be_silent must_throw].freeze

        RESTRICT_ON_SEND = VALUE_MATCHERS + BLOCK_MATCHERS

        VALUE_MATCHERS_STR = VALUE_MATCHERS.map do |m|
          ":#{m}"
        end.join(' ').freeze

        BLOCK_MATCHERS_STR = BLOCK_MATCHERS.map do |m|
          ":#{m}"
        end.join(' ').freeze

        # There are aliases for the `_` method - `expect` and `value`
        DSL_METHODS_LIST = %w[_ value expect].map do |n|
          ":#{n}"
        end.join(' ').freeze

        def_node_matcher :value_global_expectation?, <<~PATTERN
          (send !(send nil? {#{DSL_METHODS_LIST}} _) {#{VALUE_MATCHERS_STR}} ...)
        PATTERN

        def_node_matcher :block_global_expectation?, <<~PATTERN
          (send
            [
              !(send nil? {#{DSL_METHODS_LIST}} _)
              !(block (send nil? {#{DSL_METHODS_LIST}}) _ _)
            ]
            {#{BLOCK_MATCHERS_STR}}
            _
          )
        PATTERN

        def on_send(node)
          return unless value_global_expectation?(node) || block_global_expectation?(node)

          message = format(MSG, preferred: preferred_receiver(node))

          add_offense(node.receiver.source_range, message: message) do |corrector|
            receiver = node.receiver.source_range

            if BLOCK_MATCHERS.include?(node.method_name)
              corrector.wrap(receiver, '_ { ', ' }')
            else
              corrector.wrap(receiver, '_(', ')')
            end
          end
        end

        private

        def preferred_receiver(node)
          source = node.receiver.source
          if BLOCK_MATCHERS.include?(node.method_name)
            "_ { #{source} }"
          else
            "_(#{source})"
          end
        end
      end
    end
  end
end
