require 'cucumber/messages/varint'

module Cucumber
  module Messages
    class NdjsonToMessageEnumerator < Enumerator
      def initialize(io)
        super() do |yielder|
          io.each_line do |line|
            next if line.strip.empty?
            begin
              m = Cucumber::Messages::Envelope.from_json(line)
            rescue => e
              raise "Not JSON: #{line.strip}"
            end
            yielder.yield(m)
          end
        end
      end
    end
  end
end
