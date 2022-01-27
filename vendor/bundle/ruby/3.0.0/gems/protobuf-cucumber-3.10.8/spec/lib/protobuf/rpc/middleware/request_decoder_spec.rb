require 'spec_helper'

RSpec.describe Protobuf::Rpc::Middleware::RequestDecoder do
  let(:app) { proc { |env| env } }
  let(:client_host) { 'client_host.test.co' }
  let(:env) do
    Protobuf::Rpc::Env.new(
      'encoded_request' => encoded_request,
      'log_signature' => 'log_signature',
    )
  end
  let(:encoded_request) { request_wrapper.encode }
  let(:method_name) { :find }
  let(:request) { request_type.new(:name => 'required') }
  let(:request_type) { rpc_method.request_type }
  let(:request_wrapper) do
    ::Protobuf::Socketrpc::Request.new(
      :caller => client_host,
      :service_name => service_name,
      :method_name => method_name.to_s,
      :request_proto => request,
    )
  end
  let(:response_type) { rpc_method.response_type }
  let(:rpc_method) { rpc_service.rpcs[method_name] }
  let(:rpc_service) { Test::ResourceService }
  let(:service_name) { rpc_service.to_s }

  subject { described_class.new(app) }

  describe "#call" do
    it "decodes the request" do
      stack_env = subject.call(env)
      expect(stack_env.request).to eq request
    end

    it "calls the stack" do
      expect(app).to receive(:call).with(env)
      subject.call(env)
    end

    it "sets Env#client_host" do
      stack_env = subject.call(env)
      expect(stack_env.client_host).to eq client_host
    end

    it "sets Env#service_name" do
      stack_env = subject.call(env)
      expect(stack_env.service_name).to eq service_name
    end

    it "sets Env#method_name" do
      stack_env = subject.call(env)
      expect(stack_env.method_name).to eq method_name.to_sym
    end

    it "sets Env#request_type" do
      stack_env = subject.call(env)
      expect(stack_env.request_type).to eq request_type
    end

    it "sets Env#response_type" do
      stack_env = subject.call(env)
      expect(stack_env.response_type).to eq response_type
    end

    it "sets Env#rpc_method" do
      stack_env = subject.call(env)
      expect(stack_env.rpc_method).to eq rpc_method
    end

    it "sets Env#rpc_service" do
      stack_env = subject.call(env)
      expect(stack_env.rpc_service).to eq rpc_service
    end

    context "when decoding fails" do
      before { allow(::Protobuf::Socketrpc::Request).to receive(:decode).and_raise(RuntimeError) }

      it "raises a bad request data exception" do
        expect { subject.call(env) }.to raise_exception(Protobuf::Rpc::BadRequestData)
      end
    end

    context "when the RPC service is not defined" do
      let(:request_wrapper) do
        ::Protobuf::Socketrpc::Request.new(
          :caller => client_host,
          :service_name => 'NonexistantService',
          :method_name => method_name.to_s,
          :request_proto => request,
        )
      end

      it "raises a bad request data exception" do
        expect { subject.call(env) }.to raise_exception(Protobuf::Rpc::ServiceNotFound)
      end
    end

    context "when RPC method is not defined" do
      let(:request_wrapper) do
        ::Protobuf::Socketrpc::Request.new(
          :caller => client_host,
          :service_name => service_name,
          :method_name => 'foo',
          :request_proto => request,
        )
      end

      it "raises a bad request data exception" do
        expect { subject.call(env) }.to raise_exception(Protobuf::Rpc::MethodNotFound)
      end
    end
  end
end
