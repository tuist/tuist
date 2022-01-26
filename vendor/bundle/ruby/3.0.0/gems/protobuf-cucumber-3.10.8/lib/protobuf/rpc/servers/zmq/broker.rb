require 'thread'

module Protobuf
  module Rpc
    module Zmq
      class Broker
        include ::Protobuf::Rpc::Zmq::Util

        attr_reader :local_queue

        def initialize(server)
          @server = server

          init_zmq_context
          init_local_queue
          init_backend_socket
          init_frontend_socket
          init_poller
        rescue
          teardown
          raise
        end

        def run
          @idle_workers = []
          @running = true

          loop do
            process_local_queue
            rc = @poller.poll(broker_polling_milliseconds)

            # The server was shutdown and no requests are pending
            break if rc == 0 && !running? && @server.workers.empty?
            # Something went wrong
            break if rc == -1

            check_and_process_backend
            process_local_queue # Fair ordering so queued requests get in before new requests
            check_and_process_frontend
          end
        ensure
          teardown
          @running = false
        end

        def running?
          @running && @server.running?
        end

        private

        def backend_poll_weight
          @backend_poll_weight ||= [ENV["PB_ZMQ_SERVER_BACKEND_POLL_WEIGHT"].to_i, 1].max
        end

        def broker_polling_milliseconds
          @broker_polling_milliseconds ||= [ENV["PB_ZMQ_BROKER_POLLING_MILLISECONDS"].to_i, 500].max
        end

        def check_and_process_backend
          readables_include_backend = @poller.readables.include?(@backend_socket)
          message_count_read_from_backend = 0

          while readables_include_backend && message_count_read_from_backend < backend_poll_weight
            message_count_read_from_backend += 1
            process_backend
            @poller.poll_nonblock
            readables_include_backend = @poller.readables.include?(@backend_socket)
          end
        end

        def check_and_process_frontend
          readables_include_frontend = @poller.readables.include?(@frontend_socket)
          message_count_read_from_frontend = 0

          while readables_include_frontend && message_count_read_from_frontend < frontend_poll_weight
            message_count_read_from_frontend += 1
            process_frontend
            break unless local_queue_available? # no need to read frontend just to throw away messages, will prioritize backend when full
            @poller.poll_nonblock
            readables_include_frontend = @poller.readables.include?(@frontend_socket)
          end
        end

        def frontend_poll_weight
          @frontend_poll_weight ||= [ENV["PB_ZMQ_SERVER_FRONTEND_POLL_WEIGHT"].to_i, 1].max
        end

        def init_backend_socket
          @backend_socket = @zmq_context.socket(ZMQ::ROUTER)
          zmq_error_check(@backend_socket.bind(@server.backend_uri))
        end

        def init_frontend_socket
          @frontend_socket = @zmq_context.socket(ZMQ::ROUTER)
          zmq_error_check(@frontend_socket.bind(@server.frontend_uri))
        end

        def init_local_queue
          @local_queue = []
        end

        def init_poller
          @poller = ZMQ::Poller.new
          @poller.register_readable(@frontend_socket)
          @poller.register_readable(@backend_socket)
        end

        def init_zmq_context
          @zmq_context =
            if inproc?
              @server.zmq_context
            else
              ZMQ::Context.new
            end
        end

        def inproc?
          !!@server.try(:inproc?)
        end

        def local_queue_available?
          local_queue.size < local_queue_max_size && running?
        end

        def local_queue_max_size
          @local_queue_max_size ||= [ENV["PB_ZMQ_SERVER_QUEUE_MAX_SIZE"].to_i, 5].max
        end

        def process_backend
          worker, _ignore, *frames = read_from_backend

          @idle_workers << worker

          unless frames == [::Protobuf::Rpc::Zmq::WORKER_READY_MESSAGE]
            write_to_frontend(frames)
          end
        end

        def process_frontend
          address, _, message, *frames = read_from_frontend

          if message == ::Protobuf::Rpc::Zmq::CHECK_AVAILABLE_MESSAGE
            if local_queue_available?
              write_to_frontend([address, ::Protobuf::Rpc::Zmq::EMPTY_STRING, ::Protobuf::Rpc::Zmq::WORKERS_AVAILABLE])
            else
              write_to_frontend([address, ::Protobuf::Rpc::Zmq::EMPTY_STRING, ::Protobuf::Rpc::Zmq::NO_WORKERS_AVAILABLE])
            end
          else
            if @idle_workers.empty? # rubocop:disable Style/IfInsideElse
              local_queue << [address, ::Protobuf::Rpc::Zmq::EMPTY_STRING, message].concat(frames)
            else
              write_to_backend([@idle_workers.shift, ::Protobuf::Rpc::Zmq::EMPTY_STRING].concat([address, ::Protobuf::Rpc::Zmq::EMPTY_STRING, message]).concat(frames))
            end
          end
        end

        def process_local_queue
          return if local_queue.empty?
          return if @idle_workers.empty?

          write_to_backend([@idle_workers.shift, ::Protobuf::Rpc::Zmq::EMPTY_STRING].concat(local_queue.shift))
          process_local_queue
        end

        def read_from_backend
          frames = []
          zmq_error_check(@backend_socket.recv_strings(frames))
          frames
        end

        def read_from_frontend
          frames = []
          zmq_error_check(@frontend_socket.recv_strings(frames))
          frames
        end

        def teardown
          @frontend_socket.try(:close)
          @backend_socket.try(:close)
          @zmq_context.try(:terminate) unless inproc?
        end

        def write_to_backend(frames)
          zmq_error_check(@backend_socket.send_strings(frames))
        end

        def write_to_frontend(frames)
          zmq_error_check(@frontend_socket.send_strings(frames))
        end
      end
    end
  end
end
