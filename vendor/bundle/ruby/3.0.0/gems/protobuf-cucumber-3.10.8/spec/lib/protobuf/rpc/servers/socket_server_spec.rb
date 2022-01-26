require 'spec_helper'
require 'protobuf/rpc/servers/socket_runner'
require 'protobuf/socket'
require SUPPORT_PATH.join('resource_service')

RSpec.describe Protobuf::Rpc::Socket::Server do
  before(:each) do
    load 'protobuf/socket.rb'
  end

  before(:all) do
    load 'protobuf/socket.rb'
    Thread.abort_on_exception = true
    @options = OpenStruct.new(:host => "127.0.0.1", :port => 9399, :backlog => 100, :threshold => 100)
    @runner = ::Protobuf::Rpc::SocketRunner.new(@options)
    @server = @runner.instance_variable_get(:@server)
    @server_thread = Thread.new(@runner, &:run)
    Thread.pass until @server.running?
  end

  after(:all) do
    @server.stop
    @server_thread.join
  end

  it "Runner provides a stop method" do
    expect(@runner).to respond_to(:stop)
  end

  it "provides a stop method" do
    expect(@server).to respond_to(:stop)
  end

  it "signals the Server is running" do
    expect(@server).to be_running
  end

end
