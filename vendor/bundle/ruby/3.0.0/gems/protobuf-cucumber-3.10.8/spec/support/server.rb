require 'ostruct'

require 'active_support/core_ext/hash/reverse_merge'

require 'spec_helper'
require 'protobuf/logging'
require 'protobuf/rpc/server'
require 'protobuf/rpc/servers/socket/server'
require 'protobuf/rpc/servers/socket_runner'
require 'protobuf/rpc/servers/zmq/server'
require 'protobuf/rpc/servers/zmq_runner'
require SUPPORT_PATH.join('resource_service')

# Want to abort if server dies?
Thread.abort_on_exception = true

class StubServer
  include Protobuf::Logging

  private

  attr_accessor :options, :runner, :runner_thread

  public

  def initialize(options = {})
    self.options = OpenStruct.new(
      options.reverse_merge(
        :host => '127.0.0.1',
        :port => 9399,
        :worker_port => 9400,
        :delay => 0,
        :server => Protobuf::Rpc::Socket::Server,
      ),
    )

    start
    yield self
  ensure
    stop
  end

  def start
    runner_class = {
      ::Protobuf::Rpc::Zmq::Server => ::Protobuf::Rpc::ZmqRunner,
      ::Protobuf::Rpc::Socket::Server => ::Protobuf::Rpc::SocketRunner,
    }.fetch(options.server)

    self.runner = runner_class.new(options)
    self.runner_thread = Thread.new(runner, &:run)
    runner_thread.abort_on_exception = true # Set for testing purposes
    Thread.pass until runner.running?

    logger.debug { sign_message("Server started #{options.host}:#{options.port}") }
  end

  def stop
    runner.stop
    runner_thread.join
  end

  def log_signature
    @_log_signature ||= "[stub-server]"
  end
end
