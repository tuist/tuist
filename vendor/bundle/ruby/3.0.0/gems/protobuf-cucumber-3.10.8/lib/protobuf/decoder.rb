module Protobuf
  class Decoder

    # Read bytes from +stream+ and pass to +message+ object.
    def self.decode_each_field(stream)
      until stream.eof?
        bits = Varint.decode(stream)
        wire_type = bits & 0x07
        tag = bits >> 3

        bytes = if wire_type == ::Protobuf::WireType::VARINT
                  Varint.decode(stream)
                elsif wire_type == ::Protobuf::WireType::LENGTH_DELIMITED
                  value_length = Varint.decode(stream)
                  stream.read(value_length)
                elsif wire_type == ::Protobuf::WireType::FIXED64
                  stream.read(8)
                elsif wire_type == ::Protobuf::WireType::FIXED32
                  stream.read(4)
                else
                  fail InvalidWireType, wire_type
                end

        yield(tag, bytes)
      end
    end
  end
end
