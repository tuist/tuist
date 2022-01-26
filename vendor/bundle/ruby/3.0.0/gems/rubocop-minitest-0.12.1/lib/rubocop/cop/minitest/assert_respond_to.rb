# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the use of `assert_respond_to(object, :do_something)`
      # over `assert(object.respond_to?(:do_something))`.
      #
      # @example
      #   # bad
      #   assert(object.respond_to?(:do_something))
      #   assert(object.respond_to?(:do_something), 'message')
      #   assert(respond_to?(:do_something))
      #
      #   # good
      #   assert_respond_to(object, :do_something)
      #   assert_respond_to(object, :do_something, 'message')
      #   assert_respond_to(self, :do_something)
      #
      class AssertRespondTo < Base
        extend MinitestCopRule

        define_rule :assert, target_method: :respond_to?
      end
    end
  end
end
