require 'spec_helper'

class UtilTest
  include ::Protobuf::Rpc::Zmq::Util
end

RSpec.describe ::Protobuf::Rpc::Zmq::Util do
  before(:each) do
    load 'protobuf/zmq.rb'
  end

  subject { UtilTest.new }
  describe '#zmq_error_check' do
    it 'raises when the error code is less than 0' do
      expect do
        subject.zmq_error_check(-1, :test)
      end.to raise_error(/test/)
    end

    it 'retrieves the error string from ZeroMQ' do
      allow(ZMQ::Util).to receive(:error_string).and_return('an error from zmq')
      expect do
        subject.zmq_error_check(-1, :test)
      end.to raise_error(RuntimeError, /an error from zmq/i)
    end

    it 'does nothing if the error code is > 0' do
      expect do
        subject.zmq_error_check(1, :test)
      end.to_not raise_error
    end

    it 'does nothing if the error code is == 0' do
      expect do
        subject.zmq_error_check(0, :test)
      end.to_not raise_error
    end
  end

  describe '#log_signature' do
    it 'returns the signature for the log' do
      expect(subject.log_signature).to include('server', 'UtilTest')
    end
  end

  describe '.resolve_ip' do
    it 'resolves ips' do
      expect(subject.resolve_ip('127.0.0.1')).to eq('127.0.0.1')
    end

    it 'resolves non ips' do
      expect(subject.resolve_ip('localhost')).to eq('127.0.0.1')
    end
  end
end
