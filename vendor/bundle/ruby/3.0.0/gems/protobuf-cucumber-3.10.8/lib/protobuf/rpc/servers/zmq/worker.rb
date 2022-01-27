require 'protobuf/rpc/server'
require 'protobuf/rpc/servers/zmq/util'
require 'thread'

module Protobuf
  module Rpc
    module Zmq
      class Worker
        include ::Protobuf::Rpc::Server
        include ::Protobuf::Rpc::Zmq::Util

        ##
        # Constructor
        #
        def initialize(server, broker)
          @server = server
          @broker = broker

          init_zmq_context
          init_backend_socket
        rescue
          teardown
          raise
        end

        ##
        # Instance Methods
        #
        def process_request
          client_address, _, data = read_from_backend
          return unless data

          gc_pause do
            encoded_response = handle_request(data)
            write_to_backend([client_address, ::Protobuf::Rpc::Zmq::EMPTY_STRING, encoded_response])
          end
        end

        def run
          poller = ::ZMQ::Poller.new
          poller.register_readable(@backend_socket)
          poller.register_readable(@shutdown_socket)

          # Send request to broker telling it we are ready
          write_to_backend([::Protobuf::Rpc::Zmq::WORKER_READY_MESSAGE])

          loop do
            rc = poller.poll(500)

            if rc == 0 && !running? # rubocop:disable Style/GuardClause
              break # The server was shutdown and no requests are pending
            elsif rc == -1
              break # Something went wrong
            elsif rc > 0
              ::Thread.current[:busy] = true
              process_request
              ::Thread.current[:busy] = false
            end
          end
        ensure
          teardown
        end

        def running?
          @broker.running? && @server.running?
        end

        private

        def init_zmq_context
          @zmq_context =
            if inproc?
              @server.zmq_context
            else
              ZMQ::Context.new
            end
        end

        def init_backend_socket
          @backend_socket = @zmq_context.socket(ZMQ::REQ)
          zmq_error_check(@backend_socket.connect(@server.backend_uri))
        end

        def inproc?
          !!@server.try(:inproc?)
        end

        def read_from_backend
          frames = []
          zmq_error_check(@backend_socket.recv_strings(frames))
          frames
        end

        def teardown
          @backend_socket.try(:close)
          @zmq_context.try(:terminate) unless inproc?
        end

        def write_to_backend(frames)
          zmq_error_check(@backend_socket.send_strings(frames))
        end
      end
    end
  end
end
