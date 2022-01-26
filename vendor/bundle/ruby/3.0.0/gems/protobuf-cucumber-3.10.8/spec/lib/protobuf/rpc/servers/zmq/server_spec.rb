require 'spec_helper'
require 'protobuf/rpc/servers/zmq/server'

RSpec.describe Protobuf::Rpc::Zmq::Server do
  subject { described_class.new(options) }

  let(:options) do
    {
      :host => '127.0.0.1',
      :port => 9399,
      :worker_port => 9400,
      :workers_only => true,
    }
  end

  before do
    load 'protobuf/zmq.rb'
  end

  after do
    subject.teardown
  end

  describe '.running?' do
    it 'returns true if running' do
      subject.instance_variable_set(:@running, true)
      expect(subject.running?).to be true
    end

    it 'returns false if not running' do
      subject.instance_variable_set(:@running, false)
      expect(subject.running?).to be false
    end
  end

  describe '.stop' do
    it 'sets running to false' do
      subject.instance_variable_set(:@workers, [])
      subject.stop
      expect(subject.instance_variable_get(:@running)).to be false
    end
  end
end
