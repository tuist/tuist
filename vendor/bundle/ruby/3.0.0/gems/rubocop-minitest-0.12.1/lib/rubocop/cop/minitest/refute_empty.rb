# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces to use `refute_empty` instead of
      # using `refute(object.empty?)`.
      #
      # @example
      #   # bad
      #   refute(object.empty?)
      #   refute(object.empty?, 'message')
      #
      #   # good
      #   refute_empty(object)
      #   refute_empty(object, 'message')
      #
      class RefuteEmpty < Base
        extend MinitestCopRule

        define_rule :refute, target_method: :empty?
      end
    end
  end
end
