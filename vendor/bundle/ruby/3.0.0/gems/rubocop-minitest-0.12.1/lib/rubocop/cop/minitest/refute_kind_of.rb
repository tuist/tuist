# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the use of `refute_kind_of(Class, object)`
      # over `refute(object.kind_of?(Class))`.
      #
      # @example
      #   # bad
      #   refute(object.kind_of?(Class))
      #   refute(object.kind_of?(Class), 'message')
      #
      #   # good
      #   refute_kind_of(Class, object)
      #   refute_kind_of(Class, object, 'message')
      #
      class RefuteKindOf < Base
        extend MinitestCopRule

        define_rule :refute, target_method: :kind_of?, inverse: true
      end
    end
  end
end
