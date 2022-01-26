require 'cucumber/messages/varint'

module Cucumber
  module Messages
    class BinaryToMessageEnumerator < Enumerator
      def initialize(io)
        super() do |yielder|
          while !io.eof?
            yielder.yield(Cucumber::Messages::Envelope.parse_delimited_from(io))
          end
        end
      end
    end
  end
end
