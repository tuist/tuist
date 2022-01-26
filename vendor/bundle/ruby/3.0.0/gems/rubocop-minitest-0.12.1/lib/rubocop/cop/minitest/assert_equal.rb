# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the use of `assert_equal(expected, actual)`
      # over `assert(expected == actual)`.
      #
      # @example
      #   # bad
      #   assert("rubocop-minitest" == actual)
      #
      #   # good
      #   assert_equal("rubocop-minitest", actual)
      #
      class AssertEqual < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :==, preferred_method: :assert_equal
      end
    end
  end
end
