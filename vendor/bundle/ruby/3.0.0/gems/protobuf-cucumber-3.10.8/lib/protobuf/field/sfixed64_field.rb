require 'protobuf/field/int64_field'

module Protobuf
  module Field
    class Sfixed64Field < Int64Field

      ##
      # Public Instance Methods
      #

      def decode(bytes)
        values = bytes.unpack('VV') # 'Q' is machine-dependent, don't use
        value  = values[0] + (values[1] << 32)
        value -= 0x1_0000_0000_0000_0000 if (value & 0x8000_0000_0000_0000).nonzero?
        value
      end

      def encode(value)
        [value & 0xffff_ffff, value >> 32].pack('VV') # 'Q' is machine-dependent, don't use
      end

      def wire_type
        ::Protobuf::WireType::FIXED64
      end

    end
  end
end
