require 'protobuf/field/base_field'

module Protobuf
  module Field
    class FloatField < BaseField

      ##
      # Class Methods
      #

      def self.default
        0.0
      end

      ##
      # Public Instance Methods
      #

      def acceptable?(val)
        val.respond_to?(:to_f)
      end

      def coerce!(val)
        Float(val)
      rescue ArgumentError
        fail TypeError, "Expected value of type '#{type_class}' for field #{name}, but got '#{val.class}'"
      end

      def decode(bytes)
        bytes.unpack('e').first
      end

      def encode(value)
        [value].pack('e')
      end

      def wire_type
        WireType::FIXED32
      end

    end
  end
end
