require 'spec_helper'
require 'protobuf/socket'

RSpec.shared_examples "a Protobuf Connector" do
  subject { described_class.new({}) }

  context "API" do
    # Check the API
    specify { expect(subject.respond_to?(:send_request, true)).to be true }
    specify { expect(subject.respond_to?(:post_init, true)).to be true }
    specify { expect(subject.respond_to?(:close_connection, true)).to be true }
    specify { expect(subject.respond_to?(:error?, true)).to be true }
  end
end

RSpec.describe Protobuf::Rpc::Connectors::Socket do
  subject { described_class.new({}) }

  it_behaves_like "a Protobuf Connector"

  context "#read_response" do
    let(:data) { "New data" }

    it "fills the buffer with data from the socket" do
      socket = StringIO.new("#{data.bytesize}-#{data}")
      subject.instance_variable_set(:@socket, socket)
      subject.instance_variable_set(:@stats, OpenStruct.new)
      expect(subject).to receive(:parse_response).and_return(true)

      subject.__send__(:read_response)
      expect(subject.instance_variable_get(:@response_data)).to eq(data)
    end
  end
end
