require 'protobuf/field/base_field'

module Protobuf
  module Field
    class MessageField < BaseField

      ##
      # Public Instance Methods
      #

      def acceptable?(val)
        val.is_a?(type_class) || val.respond_to?(:to_hash) || val.respond_to?(:to_proto)
      end

      def decode(bytes)
        type_class.decode(bytes)
      end

      def encode(value)
        bytes = value.encode
        result = ::Protobuf::Field::VarintField.encode(bytes.bytesize)
        result << bytes
      end

      def message?
        true
      end

      def wire_type
        ::Protobuf::WireType::LENGTH_DELIMITED
      end

      def coerce!(value)
        return nil if value.nil?

        coerced_value = if value.respond_to?(:to_proto)
                          value.to_proto
                        elsif value.respond_to?(:to_hash)
                          type_class.new(value.to_hash)
                        else
                          value
                        end

        return coerced_value if coerced_value.is_a?(type_class)

        fail TypeError, "Expected value of type '#{type_class}' for field #{name}, but got '#{value.class}'"
      end

    end
  end
end
