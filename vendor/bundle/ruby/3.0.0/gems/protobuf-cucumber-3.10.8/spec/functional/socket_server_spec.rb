require 'spec_helper'
require SUPPORT_PATH.join('resource_service')

RSpec.describe 'Functional Socket Client' do
  before(:all) do
    load "protobuf/socket.rb"
    @options = OpenStruct.new(:host => "127.0.0.1", :port => 9399, :backlog => 100, :threshold => 100)
    @runner = ::Protobuf::Rpc::SocketRunner.new(@options)
    @server_thread = Thread.new(@runner, &:run)
    Thread.pass until @runner.running?
  end

  after(:all) do
    @runner.stop
    @server_thread.join
  end

  it 'runs fine when required fields are set' do
    expect do
      client = ::Test::ResourceService.client

      client.find(:name => 'Test Name', :active => true) do |c|
        c.on_success do |succ|
          expect(succ.name).to eq("Test Name")
          expect(succ.status).to eq(::Test::StatusType::ENABLED)
        end

        c.on_failure do |err|
          fail err.inspect
        end
      end
    end.to_not raise_error
  end

  it 'calls the on_failure callback when a message is malformed' do
    error = nil
    request = ::Test::ResourceFindRequest.new(:active => true)
    client = ::Test::ResourceService.client

    client.find(request) do |c|
      c.on_success { fail "shouldn't pass" }
      c.on_failure { |e| error = e }
    end

    expect(error.message).to match(/Required field.*does not have a value/)
  end

  it 'calls the on_failure callback when the request type is wrong' do
    error = nil
    request = ::Test::Resource.new(:name => 'Test Name')
    client = ::Test::ResourceService.client

    client.find(request) do |c|
      c.on_success { fail "shouldn't pass" }
      c.on_failure { |e| error = e }
    end
    expect(error.message).to match(/expected request.*ResourceFindRequest.*Resource instead/i)
  end
end
