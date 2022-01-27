module Protobuf
  class Encoder
    def self.encode(message, stream)
      message.each_field_for_serialization do |field, value|
        field.encode_to_stream(value, stream)
      end

      stream
    end
  end
end
