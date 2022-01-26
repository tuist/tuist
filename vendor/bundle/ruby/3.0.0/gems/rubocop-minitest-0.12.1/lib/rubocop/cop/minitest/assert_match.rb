# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_match`
      # instead of using `assert(matcher.match(string))`.
      #
      # @example
      #   # bad
      #   assert(matcher.match(string))
      #   assert(matcher.match(string), 'message')
      #
      #   # good
      #   assert_match(regex, string)
      #   assert_match(matcher, string, 'message')
      #
      class AssertMatch < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :match
      end
    end
  end
end
