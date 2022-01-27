require 'protobuf/field/varint_field'

module Protobuf
  module Field
    class BoolField < VarintField
      ONE = 1
      FALSE_ENCODE = [0].pack('C')
      FALSE_STRING = "false".freeze
      FALSE_VALUES = [false, FALSE_STRING].freeze
      TRUE_ENCODE = [1].pack('C')
      TRUE_STRING = "true".freeze
      TRUE_VALUES = [true, TRUE_STRING].freeze
      ACCEPTABLES = [true, false, TRUE_STRING, FALSE_STRING].freeze

      ##
      # Class Methods
      #

      def self.default
        false
      end

      ##
      # Public Instance Methods
      # #

      def acceptable?(val)
        ACCEPTABLES.include?(val)
      end

      def coerce!(val)
        if TRUE_VALUES.include?(val)
          true
        elsif FALSE_VALUES.include?(val)
          false
        else
          fail TypeError, "Expected value of type '#{type_class}' for field #{name}, but got '#{val.class}'"
        end
      end

      def decode(value)
        value == ONE
      end

      def encode(value)
        value ? TRUE_ENCODE : FALSE_ENCODE
      end

      private

      ##
      # Private Instance Methods
      #

      def define_accessor(simple_field_name, _fully_qualified_field_name)
        super
        message_class.class_eval do
          alias_method "#{simple_field_name}?", simple_field_name
        end
      end

    end
  end
end
