require 'spec_helper'

RSpec.describe ::Protobuf::Rpc::Zmq::Worker do
  before(:each) do
    load 'protobuf/zmq.rb'

    fake_socket = double
    expect(fake_socket).to receive(:connect).and_return(0)
    expect(fake_socket).to receive(:send_string).and_return(0)

    fake_context = double
    expect(fake_context).to receive(:socket).and_return(fake_socket)
    expect(::ZMQ::Context).to receive(:new).and_return(fake_context)
  end

  subject do
    described_class.new(:host => '127.0.0.1', :port => 9400)
  end

  describe '#run' do
    # not tested via unit tests
  end

  describe '#handle_request' do
    # not tested via unit tests
  end

  describe '#initialize_buffers' do
    # not tested via unit tests
  end

  describe '#send_data' do
    # not tested via unit tests
  end
end
