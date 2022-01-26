require 'stringio'
require 'protobuf/decoder'
require 'protobuf/encoder'

module Protobuf
  class Message
    module Serialization

      module ClassMethods
        def decode(bytes)
          new.decode(bytes)
        end

        def decode_from(stream)
          new.decode_from(stream)
        end

        # Create a new object with the given values and return the encoded bytes.
        def encode(fields = {})
          new(fields).encode
        end
      end

      def self.included(other)
        other.extend(ClassMethods)
      end

      ##
      # Instance Methods
      #

      # Decode the given non-stream bytes into this message.
      #
      def decode(bytes)
        decode_from(::StringIO.new(bytes))
      end

      # Decode the given stream into this message.
      #
      def decode_from(stream)
        ::Protobuf::Decoder.decode_each_field(stream) do |tag, bytes|
          set_field_bytes(tag, bytes)
        end

        self
      end

      # Encode this message
      #
      def encode
        stream = ::StringIO.new
        stream.set_encoding(::Protobuf::Field::BytesField::BYTES_ENCODING)
        encode_to(stream)
        stream.string
      end

      # Encode this message to the given stream.
      #
      def encode_to(stream)
        ::Protobuf::Encoder.encode(self, stream)
      end

      ##
      # Instance Aliases
      #
      alias :parse_from_string decode
      alias :deserialize decode
      alias :parse_from decode_from
      alias :deserialize_from decode_from
      alias :to_s encode
      alias :bytes encode
      alias :serialize encode
      alias :serialize_to_string encode
      alias :serialize_to encode_to

      private

      def set_field_bytes(tag, bytes)
        field = _protobuf_message_field[tag]
        field.set(self, bytes) if field
      end

    end
  end
end
