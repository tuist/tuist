require 'cucumber/wire/data_packet'

module Cucumber
  module Wire
    describe DataPacket do
      describe "#to_json" do
        it "converts params to a JSON hash" do
          packet = DataPacket.new('test_message', :foo => :bar)

          expect(packet.to_json).to eq "[\"test_message\",{\"foo\":\"bar\"}]"
        end

        it "does not pass blank params" do
          packet = DataPacket.new('test_message')

          expect(packet.to_json).to eq "[\"test_message\"]"
        end
      end

      describe ".parse" do
        it "understands a raw packet containing null parameters" do
          packet = DataPacket.parse("[\"test_message\",null]")

          expect(packet.message).to eq 'test_message'
          expect(packet.params).to be_nil
        end

        it "understands a raw packet containing no parameters" do
          packet = DataPacket.parse("[\"test_message\"]")

          expect(packet.message).to eq 'test_message'
          expect(packet.params).to be_nil
        end

        it "understands a raw packet containging parameters data" do
          packet = DataPacket.parse("[\"test_message\",{\"foo\":\"bar\"}]")

          expect(packet.params['foo']).to eq 'bar'
        end
      end
    end
  end
end
