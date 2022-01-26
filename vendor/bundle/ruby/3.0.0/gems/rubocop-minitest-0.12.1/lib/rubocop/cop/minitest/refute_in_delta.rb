# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `refute_in_delta`
      # instead of using `refute_equal` to compare floats.
      #
      # @example
      #   # bad
      #   refute_equal(0.2, actual)
      #   refute_equal(0.2, actual, 'message')
      #
      #   # good
      #   refute_in_delta(0.2, actual)
      #   refute_in_delta(0.2, actual, 0.001, 'message')
      #
      class RefuteInDelta < Base
        include InDeltaMixin
        extend AutoCorrector

        RESTRICT_ON_SEND = %i[refute_equal].freeze

        def_node_matcher :equal_floats_call, <<~PATTERN
          (send nil? :refute_equal $_ $_ $...)
        PATTERN
      end
    end
  end
end
