require 'spec_helper'
require SUPPORT_PATH.join('resource_service')

RSpec.describe Protobuf::Rpc::Service do

  context 'class methods' do
    subject { Test::ResourceService }

    before :each do
      reset_service_location Test::ResourceService
    end

    describe '.host' do
      specify { expect(subject.host).to eq described_class::DEFAULT_HOST }
    end

    describe '.host=' do
      before { subject.host = 'mynewhost.com' }
      specify { expect(subject.host).to eq 'mynewhost.com' }
    end

    describe '.port' do
      specify { expect(subject.port).to eq described_class::DEFAULT_PORT }
    end

    describe '.port=' do
      before { subject.port = 12345 }
      specify { expect(subject.port).to eq 12345 }
    end

    describe '.configure' do
      context 'when providing a host' do
        before { subject.configure(:host => 'mynewhost.com') }
        specify { expect(subject.host).to eq 'mynewhost.com' }
      end

      context 'when providing a port' do
        before { subject.configure(:port => 12345) }
        specify { expect(subject.port).to eq 12345 }
      end
    end

    describe '.located_at' do
      context 'when given location is empty' do
        before { subject.located_at(nil) }
        specify { expect(subject.host).to eq described_class::DEFAULT_HOST }
        specify { expect(subject.port).to eq described_class::DEFAULT_PORT }
      end

      context 'when given location is invalid' do
        before { subject.located_at('i like pie') }
        specify { expect(subject.host).to eq described_class::DEFAULT_HOST }
        specify { expect(subject.port).to eq described_class::DEFAULT_PORT }
      end

      context 'when given location contains a host and port' do
        before { subject.located_at('mynewdomain.com:12345') }
        specify { expect(subject.host).to eq 'mynewdomain.com' }
        specify { expect(subject.port).to eq 12345 }
      end
    end

    describe '.client' do
      it 'initializes a client object for this service' do
        client = double('client')
        expect(::Protobuf::Rpc::Client).to receive(:new)
          .with(hash_including(
                  :service => subject,
                  :host => subject.host,
                  :port => subject.port,
          )).and_return(client)
        expect(subject.client).to eq client
      end
    end

    describe '.rpc' do
      before { Test::ResourceService.rpc(:update, Test::ResourceFindRequest, Test::Resource) }
      subject { Test::ResourceService.rpcs[:update] }
      specify { expect(subject.method).to eq :update }
      specify { expect(subject.request_type).to eq Test::ResourceFindRequest }
      specify { expect(subject.response_type).to eq Test::Resource }
    end

    describe '.rpc_method?' do
      before { Test::ResourceService.rpc(:delete, Test::Resource, Test::Resource) }

      context 'when given name is a pre-defined rpc method' do
        it 'returns true' do
          expect(subject.rpc_method?(:delete)).to be true
        end
      end

      context 'when given name is not a pre-defined rpc method' do
        it 'returns false' do
          expect(subject.rpc_method?(:zoobaboo)).to be false
        end
      end
    end
  end

  context 'instance methods' do
    context 'when invoking a service call' do
      before do
        stub_const('NewTestService', Class.new(Protobuf::Rpc::Service) do
          rpc :find_with_implied_response, Test::ResourceFindRequest, Test::Resource
          def find_with_implied_response
            response.name = 'Implicit response'
          end

          rpc :find_with_respond_with, Test::ResourceFindRequest, Test::Resource
          def find_with_respond_with
            custom = Test::Resource.new(:name => 'Custom response')
            respond_with(custom)
          end

          rpc :find_with_rpc_failed, Test::ResourceFindRequest, Test::Resource
          def find_with_rpc_failed
            rpc_failed('This is a failed endpoint')
            response.name = 'Name will still be set'
          end
        end)
      end

      let(:request) { Test::ResourceFindRequest.new(:name => 'resource') }
      let(:response) { Test::Resource.new }

      context 'when calling the rpc method' do
        context 'when response is implied' do
          let(:env) do
            Protobuf::Rpc::Env.new(
              'request' => request,
              'response_type' => response_type,
            )
          end
          let(:response_type) { service.rpcs[:find_with_implied_response].response_type }
          let(:service) { NewTestService }

          subject { NewTestService.new(env) }

          before { subject.find_with_implied_response }
          specify { expect(subject.response).to be_a(Test::Resource) }
          specify { expect(subject.response.name).to eq 'Implicit response' }
        end

        context 'when using respond_with paradigm' do
          let(:env) do
            Protobuf::Rpc::Env.new(
              'method_name' => :find_with_respond_with,
              'request' => request,
            )
          end

          subject { NewTestService.new(env) }

          before { subject.find_with_respond_with }
          specify { expect(subject.response).to be_a(Test::Resource) }
          specify { expect(subject.response.name).to eq 'Custom response' }
        end
      end
    end
  end
end
