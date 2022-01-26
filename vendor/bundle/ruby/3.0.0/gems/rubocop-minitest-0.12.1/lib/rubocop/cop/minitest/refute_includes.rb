# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the test to use `refute_includes`
      # instead of using `refute(collection.include?(object))`.
      #
      # @example
      #   # bad
      #   refute(collection.include?(object))
      #   refute(collection.include?(object), 'message')
      #
      #   # good
      #   refute_includes(collection, object)
      #   refute_includes(collection, object, 'message')
      #
      class RefuteIncludes < Base
        extend MinitestCopRule

        define_rule :refute, target_method: :include?, preferred_method: :refute_includes
      end
    end
  end
end
