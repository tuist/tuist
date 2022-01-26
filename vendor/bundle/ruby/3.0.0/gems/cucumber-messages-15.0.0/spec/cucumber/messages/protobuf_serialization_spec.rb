require 'cucumber/messages'

module Cucumber
  module Messages
    describe Messages do

      it "can be serialised over a binary stream" do
        outgoing_messages = [
          Envelope.new(source: Source.new(data: 'Feature: Hello')),
          Envelope.new(attachment: Attachment.new(body: "JALLA"))
        ]

        io = StringIO.new
        write_outgoing_messages(outgoing_messages, io)

        io.rewind
        incoming_messages = BinaryToMessageEnumerator.new(io)

        expect(incoming_messages.to_a).to(eq(outgoing_messages))
      end

      def write_outgoing_messages(messages, out)
        messages.each do |message|
          message.write_delimited_to(out)
        end
      end
    end
  end
end
