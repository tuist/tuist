# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `refute_respond_to(object, :do_something)`
      # over `refute(object.respond_to?(:do_something))`.
      #
      # @example
      #   # bad
      #   refute(object.respond_to?(:do_something))
      #   refute(object.respond_to?(:do_something), 'message')
      #   refute(respond_to?(:do_something))
      #
      #   # good
      #   refute_respond_to(object, :do_something)
      #   refute_respond_to(object, :do_something, 'message')
      #   refute_respond_to(self, :do_something)
      #
      class RefuteRespondTo < Base
        extend MinitestCopRule

        define_rule :refute, target_method: :respond_to?
      end
    end
  end
end
