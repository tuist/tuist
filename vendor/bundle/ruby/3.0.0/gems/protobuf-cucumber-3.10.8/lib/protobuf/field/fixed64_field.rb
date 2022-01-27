require 'protobuf/field/uint64_field'

module Protobuf
  module Field
    class Fixed64Field < Uint64Field

      ##
      # Public Instance Methods
      #

      def decode(bytes)
        # we don't use 'Q' for pack/unpack. 'Q' is machine-dependent.
        values = bytes.unpack('VV')
        values[0] + (values[1] << 32)
      end

      def encode(value)
        # we don't use 'Q' for pack/unpack. 'Q' is machine-dependent.
        [value & 0xffff_ffff, value >> 32].pack('VV')
      end

      def wire_type
        ::Protobuf::WireType::FIXED64
      end

    end
  end
end
