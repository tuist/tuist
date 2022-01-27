require 'spec_helper'
require SUPPORT_PATH.join('resource_service')

RSpec.describe Protobuf::Rpc::Client do
  before(:each) do
    load 'protobuf/socket.rb'
  end

  context 'when creating a client from a service' do
    before { reset_service_location(Test::ResourceService) }

    it 'should be able to get a client through the Service#client helper method' do
      expect(::Test::ResourceService.client(:port => 9191)).to eq(Protobuf::Rpc::Client.new(:service => Test::ResourceService, :port => 9191))
    end

    it "should be able to override a service location's host and port" do
      Test::ResourceService.located_at 'somewheregreat.com:12345'
      clean_client = Test::ResourceService.client
      expect(clean_client.options[:host]).to eq('somewheregreat.com')
      expect(clean_client.options[:port]).to eq(12345)

      updated_client = Test::ResourceService.client(:host => 'amazing.com', :port => 54321)
      expect(updated_client.options[:host]).to eq('amazing.com')
      expect(updated_client.options[:port]).to eq(54321)
    end

    it 'should be able to define which service to create itself for' do
      client = Protobuf::Rpc::Client.new :service => Test::ResourceService
      expect(client.options[:service]).to eq(Test::ResourceService)
    end

    it 'should have a hard default for host and port on a service that has not been configured' do
      client = Test::ResourceService.client
      expect(client.options[:host]).to eq(Protobuf::Rpc::Service::DEFAULT_HOST)
      expect(client.options[:port]).to eq(Protobuf::Rpc::Service::DEFAULT_PORT)
    end

  end

  context 'when calling methods on a service client' do

    # NOTE: we are assuming the service methods are accurately
    # defined inside spec/proto/test_service.rb,
    # namely the :find method

    it 'should respond to defined service methods' do
      client = Test::ResourceService.client
      expect(client).to receive(:send_request).and_return(nil)
      expect { client.find(nil) }.to_not raise_error
    end
  end

  context 'when receiving request objects' do

    it 'should be able to create the correct request object if passed a hash' do
      client = Test::ResourceService.client
      expect(client).to receive(:send_request)
      client.find(:name => 'Test Name', :active => false)
      expect(client.options[:request]).to be_a(Test::ResourceFindRequest)
      expect(client.options[:request].name).to eq('Test Name')
      expect(client.options[:request].active).to eq(false)
    end

  end

end
