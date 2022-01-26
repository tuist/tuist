require 'protobuf/field/float_field'

module Protobuf
  module Field
    class DoubleField < FloatField

      ##
      # Public Instance Methods
      #

      def decode(bytes)
        bytes.unpack('E').first
      end

      def encode(value)
        [value].pack('E')
      end

      def wire_type
        WireType::FIXED64
      end

    end
  end
end
