# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_in_delta`
      # instead of using `assert_equal` to compare floats.
      #
      # @example
      #   # bad
      #   assert_equal(0.2, actual)
      #   assert_equal(0.2, actual, 'message')
      #
      #   # good
      #   assert_in_delta(0.2, actual)
      #   assert_in_delta(0.2, actual, 0.001, 'message')
      #
      class AssertInDelta < Base
        include InDeltaMixin
        extend AutoCorrector

        RESTRICT_ON_SEND = %i[assert_equal].freeze

        def_node_matcher :equal_floats_call, <<~PATTERN
          (send nil? :assert_equal $_ $_ $...)
        PATTERN
      end
    end
  end
end
