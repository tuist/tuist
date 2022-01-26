# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_empty`
      # instead of using `assert(object.empty?)`.
      #
      # @example
      #   # bad
      #   assert(object.empty?)
      #   assert(object.empty?, 'message')
      #
      #   # good
      #   assert_empty(object)
      #   assert_empty(object, 'message')
      #
      class AssertEmpty < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :empty?
      end
    end
  end
end
