module Protobuf
  class Varint
    if defined?(::Varint)
      extend ::Varint

      def self.encode(value)
        bytes = []
        until value < 128
          bytes << (0x80 | (value & 0x7f))
          value >>= 7
        end
        (bytes << value).pack('C*')
      end
    elsif defined?(::ProtobufJavaHelpers)
      extend ::ProtobufJavaHelpers::EncodeDecode
    else
      extend VarintPure
    end
  end
end
