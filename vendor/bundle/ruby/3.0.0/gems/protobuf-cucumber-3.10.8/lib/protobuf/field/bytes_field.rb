require 'protobuf/wire_type'

module Protobuf
  module Field
    class BytesField < BaseField

      ##
      # Constants
      #

      BYTES_ENCODING = Encoding::BINARY

      ##
      # Class Methods
      #

      def self.default
        ''
      end

      ##
      # Public Instance Methods
      #

      def acceptable?(val)
        val.is_a?(String) || val.nil? || val.is_a?(Symbol) || val.is_a?(::Protobuf::Message)
      end

      def decode(bytes)
        bytes.force_encoding(::Protobuf::Field::BytesField::BYTES_ENCODING)
        bytes
      end

      def encode(value)
        value_to_encode = if value.is_a?(::Protobuf::Message)
                            value.encode
                          else
                            "" + value
                          end

        value_to_encode.force_encoding(::Protobuf::Field::BytesField::BYTES_ENCODING)
        "#{::Protobuf::Field::VarintField.encode(value_to_encode.bytesize)}#{value_to_encode}"
      end

      def wire_type
        ::Protobuf::WireType::LENGTH_DELIMITED
      end

      def coerce!(value)
        case value
        when String
          if value.encoding == Encoding::ASCII_8BIT
            # This is a "binary" string
            value
          else
            # Assume the value is Base64 encoded (from JSON)
            # Ideally we'd do the Base64 decoding while processing the JSON,
            # but this is tricky to do since we don't know the protobuf field
            # types when we do that.
            Base64.decode64(value)
          end
        when Symbol
          value.to_s
        when NilClass
          nil
        when ::Protobuf::Message
          value.dup
        else
          fail TypeError, "Unacceptable value #{value} for field #{name} of type #{type_class}"
        end
      end

      def json_encode(value, options={})
        Base64.strict_encode64(value)
      end
    end
  end
end
