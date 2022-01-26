module Cucumber
  module Messages
    # Varint (variable byte-length int) is an encoding format commonly used
    # to encode the length of Protocol Buffer message frames.
    module Varint

      def self.decode_varint(io)
        # https://github.com/ruby-protobuf/protobuf/blob/master/lib/protobuf/varint_pure.rb
        value = index = 0
        begin
          byte = io.readbyte
          value |= (byte & 0x7f) << (7 * index)
          index += 1
        end while (byte & 0x80).nonzero?
        value
      end

      # https://www.rubydoc.info/gems/ruby-protocol-buffers/1.2.2/ProtocolBuffers%2FVarint.encode
      def self.encode_varint(io, int_val)
        if int_val < 0
          # negative varints are always encoded with the full 10 bytes
          int_val = int_val & 0xffffffff_ffffffff
        end
        loop do
          byte = int_val & 0x7f
          int_val >>= 7
          if int_val == 0
            io << byte.chr
            break
          else
            io << (byte | 0x80).chr
          end
        end
      end
    end
  end
end