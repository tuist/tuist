require 'spec_helper'

require 'protobuf/rpc/service_directory'
require SUPPORT_PATH.join('resource_service')

RSpec.describe 'Functional ZMQ Client' do
  before(:all) do
    load "protobuf/zmq.rb"
    @runner = ::Protobuf::Rpc::ZmqRunner.new(
      'host' => '127.0.0.1',
      'port' => 9399,
      'worker_port' => 9408,
      'backlog' => 100,
      'threshold' => 100,
      'threads' => 5,
    )
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

  it 'runs under heavy load' do
    10.times do
      5.times.map do
        Thread.new do
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
        end
      end.each(&:join)
    end
  end

  context 'when a message is malformed' do
    it 'calls the on_failure callback' do
      error = nil
      request = ::Test::ResourceFindRequest.new(:active => true)
      client = ::Test::ResourceService.client

      client.find(request) do |c|
        c.on_success { fail "shouldn't pass" }
        c.on_failure { |e| error = e }
      end
      expect(error.message).to match(/Required field.*does not have a value/)
    end
  end

  context 'when the request type is wrong' do
    it 'calls the on_failure callback' do
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

  context 'when the server takes too long to respond' do
    it 'responds with a timeout error' do
      error = nil
      client = ::Test::ResourceService.client(:timeout => 1)

      client.find_with_sleep(:sleep => 2) do |c|
        c.on_success { fail "shouldn't pass" }
        c.on_failure { |e| error = e }
      end
      expect(error.message).to match(/The server repeatedly failed to respond/)
    end
  end

end
