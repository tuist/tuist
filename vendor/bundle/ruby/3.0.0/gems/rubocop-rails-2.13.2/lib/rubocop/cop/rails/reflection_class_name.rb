# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks if the value of the option `class_name`, in
      # the definition of a reflection is a string.
      #
      # @safety
      #   This cop is unsafe because it cannot be determined whether
      #   constant or method return value specified to `class_name` is a string.
      #
      # @example
      #   # bad
      #   has_many :accounts, class_name: Account
      #   has_many :accounts, class_name: Account.name
      #
      #   # good
      #   has_many :accounts, class_name: 'Account'
      class ReflectionClassName < Base
        MSG = 'Use a string value for `class_name`.'
        RESTRICT_ON_SEND = %i[has_many has_one belongs_to].freeze
        ALLOWED_REFLECTION_CLASS_TYPES = %i[dstr str sym].freeze

        def_node_matcher :association_with_reflection, <<~PATTERN
          (send nil? {:has_many :has_one :belongs_to} _ _ ?
            (hash <$#reflection_class_name ...>)
          )
        PATTERN

        def_node_matcher :reflection_class_name, <<~PATTERN
          (pair (sym :class_name) #reflection_class_value?)
        PATTERN

        def on_send(node)
          association_with_reflection(node) do |reflection_class_name|
            add_offense(reflection_class_name.loc.expression)
          end
        end

        private

        def reflection_class_value?(class_value)
          if class_value.send_type?
            !class_value.method?(:to_s) || class_value.receiver&.const_type?
          else
            !ALLOWED_REFLECTION_CLASS_TYPES.include?(class_value.type)
          end
        end
      end
    end
  end
end
