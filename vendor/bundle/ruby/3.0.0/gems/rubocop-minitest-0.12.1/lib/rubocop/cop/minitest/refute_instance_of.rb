# frozen_string_literal: true

module RuboCop
  module Cop
    module Minitest
      # This cop enforces the use of `refute_instance_of(Class, object)`
      # over `refute(object.instance_of?(Class))`.
      #
      # @example
      #   # bad
      #   refute(object.instance_of?(Class))
      #   refute(object.instance_of?(Class), 'message')
      #
      #   # good
      #   refute_instance_of(Class, object)
      #   refute_instance_of(Class, object, 'message')
      #
      class RefuteInstanceOf < Base
        extend MinitestCopRule

        define_rule :refute, target_method: :instance_of?, inverse: true
      end
    end
  end
end
