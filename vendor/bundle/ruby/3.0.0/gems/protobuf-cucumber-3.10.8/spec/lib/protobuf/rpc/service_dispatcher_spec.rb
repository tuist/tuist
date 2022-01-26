require 'spec_helper'
require 'protobuf/rpc/service_dispatcher'

RSpec.describe Protobuf::Rpc::ServiceDispatcher do
  let(:app) { proc { |env| env } }
  let(:env) do
    Protobuf::Rpc::Env.new(
      'method_name' => method_name,
      'request' => request,
      'rpc_service' => service_class,
      'service_name' => service_name,
    )
  end
  let(:method_name) { :find }
  let(:request) { request_type.new(:name => 'required') }
  let(:request_type) { service_class.rpcs[method_name].request_type }
  let(:response) { response_type.new(:name => 'required') }
  let(:response_type) { service_class.rpcs[method_name].response_type }
  let(:rpc_service) { service_class.new(env) }
  let(:service_class) { Test::ResourceService }
  let(:service_name) { service_class.to_s }

  subject { described_class.new(app) }

  before { allow(subject).to receive(:rpc_service).and_return(rpc_service) }

  describe '#call' do
    before { allow(rpc_service).to receive(:response).and_return(response) }

    it "dispatches the request" do
      stack_env = subject._call(env)
      expect(stack_env.response).to eq response
    end
  end
end
