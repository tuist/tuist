require 'rspec'
require 'gherkin/stream/subprocess_message_stream'

module Gherkin
  module Stream
    describe SubprocessMessageStream do
      it "works" do
        cucumber_messages = SubprocessMessageStream.new(
          "./bin/gherkin",
          ["testdata/good/minimal.feature"],
          true, true, true
        )
        messages = cucumber_messages.messages.to_a
        expect(messages.length).to eq(3)
      end
    end
  end
end
