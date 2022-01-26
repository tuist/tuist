require 'protobuf/field/uint32_field'

module Protobuf
  module Field
    class Fixed32Field < Uint32Field

      ##
      # Public Instance Methods
      #

      def decode(bytes)
        bytes.unpack('V').first
      end

      def encode(value)
        [value].pack('V')
      end

      def wire_type
        ::Protobuf::WireType::FIXED32
      end

    end
  end
end
