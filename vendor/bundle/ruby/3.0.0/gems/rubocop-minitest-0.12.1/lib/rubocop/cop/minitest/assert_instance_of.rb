# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `assert_instance_of(Class, object)`
      # over `assert(object.instance_of?(Class))`.
      #
      # @example
      #   # bad
      #   assert(object.instance_of?(Class))
      #   assert(object.instance_of?(Class), 'message')
      #
      #   # good
      #   assert_instance_of(Class, object)
      #   assert_instance_of(Class, object, 'message')
      #
      class AssertInstanceOf < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :instance_of?, inverse: true
      end
    end
  end
end
