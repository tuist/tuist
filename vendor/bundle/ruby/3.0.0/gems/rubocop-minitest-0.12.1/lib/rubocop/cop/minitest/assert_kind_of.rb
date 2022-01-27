# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_kind_of(Class, object)`
      # over `assert(object.kind_of?(Class))`.
      #
      # @example
      #   # bad
      #   assert(object.kind_of?(Class))
      #   assert(object.kind_of?(Class), 'message')
      #
      #   # good
      #   assert_kind_of(Class, object)
      #   assert_kind_of(Class, object, 'message')
      #
      class AssertKindOf < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :kind_of?, inverse: true
      end
    end
  end
end
