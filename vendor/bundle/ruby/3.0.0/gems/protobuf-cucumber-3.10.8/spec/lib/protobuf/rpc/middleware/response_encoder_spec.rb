require 'spec_helper'

RSpec.describe Protobuf::Rpc::Middleware::ResponseEncoder do
  let(:app) { proc { |env| env.response = response; env } }
  let(:env) do
    Protobuf::Rpc::Env.new(
      'response_type' => Test::Resource,
      'log_signature' => 'log_signature',
    )
  end
  let(:encoded_response) { response_wrapper.encode }
  let(:response) { Test::Resource.new(:name => 'required') }
  let(:response_wrapper) { ::Protobuf::Socketrpc::Response.new(:response_proto => response) }

  subject { described_class.new(app) }

  describe "#call" do
    it "encodes the response" do
      stack_env = subject.call(env)
      expect(stack_env.encoded_response).to eq encoded_response
    end

    it "calls the stack" do
      stack_env = subject.call(env)
      expect(stack_env.response).to eq response
    end

    context "when response is responds to :to_hash" do
      let(:app) { proc { |env| env.response = hashable; env } }
      let(:hashable) { double('hashable', :to_hash => response.to_hash) }

      it "sets Env#response" do
        stack_env = subject.call(env)
        expect(stack_env.response).to eq response
      end
    end

    context "when response is responds to :to_proto" do
      let(:app) { proc { |env| env.response = protoable; env } }
      let(:protoable) { double('protoable', :to_proto => response) }

      it "sets Env#response" do
        stack_env = subject.call(env)
        expect(stack_env.response).to eq response
      end
    end

    context "when response is not a valid response type" do
      let(:app) { proc { |env| env.response = "I'm not a valid response"; env } }

      it "raises a bad response proto exception" do
        expect { subject.call(env) }.to raise_exception(Protobuf::Rpc::BadResponseProto)
      end
    end

    context "when response is a Protobuf error" do
      let(:app) { proc { |env| env.response = error; env } }
      let(:error) { Protobuf::Rpc::RpcError.new }
      let(:response_wrapper) { error.to_response }

      it "wraps and encodes the response" do
        stack_env = subject.call(env)
        expect(stack_env.encoded_response).to eq encoded_response
      end
    end

    context "when encoding fails" do
      before { allow_any_instance_of(::Protobuf::Socketrpc::Response).to receive(:encode).and_raise(RuntimeError) }

      it "raises a bad request data exception" do
        expect { subject.call(env) }.to raise_exception(Protobuf::Rpc::PbError)
      end
    end

    context "when server exists in the env" do
      let(:env) do
        Protobuf::Rpc::Env.new(
          'response_type' => Test::Resource,
          'log_signature' => 'log_signature',
          'server'        => 'itsaserver',
        )
      end

      it "adds the servers to the response" do
        expected_response = ::Protobuf::Socketrpc::Response.new(:response_proto => response, :server => 'itsaserver').encode
        subject.call(env)
        expect(env.encoded_response).to eq(expected_response)
      end
    end
  end
end
