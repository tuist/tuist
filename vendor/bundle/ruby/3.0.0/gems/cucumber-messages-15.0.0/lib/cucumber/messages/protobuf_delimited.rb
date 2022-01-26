require 'cucumber/messages/varint'

module Cucumber
  module Messages
    module WriteDelimited
      def write_delimited_to(io)
        proto = self.class.encode(self)
        Varint.encode_varint(io, proto.length)
        io.write(proto)
      end
    end

    module ParseDelimited
      def parse_delimited_from(io)
        len = Varint.decode_varint(io)
        buf = io.read(len)
        self.decode(buf)
      end
    end
  end
end