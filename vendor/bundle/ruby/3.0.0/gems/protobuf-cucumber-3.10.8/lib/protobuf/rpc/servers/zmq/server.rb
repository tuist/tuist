require 'protobuf/rpc/servers/zmq/util'
require 'protobuf/rpc/servers/zmq/worker'
require 'protobuf/rpc/servers/zmq/broker'
require 'protobuf/rpc/dynamic_discovery.pb'
require 'securerandom'
require 'thread'

module Protobuf
  module Rpc
    module Zmq
      class Server
        include ::Protobuf::Rpc::Zmq::Util

        DEFAULT_OPTIONS = {
          :beacon_interval => 5,
          :broadcast_beacons => false,
          :broadcast_busy => false,
          :zmq_inproc => true,
        }.freeze

        attr_accessor :options, :workers
        attr_reader :zmq_context

        def initialize(options)
          @options = DEFAULT_OPTIONS.merge(options)
          @workers = []

          init_zmq_context
          init_beacon_socket if broadcast_beacons?
          init_shutdown_pipe
        rescue
          teardown
          raise
        end

        def add_worker
          @total_workers = total_workers + 1
        end

        def all_workers_busy?
          workers.all? { |thread| !!thread[:busy] }
        end

        def backend_port
          options[:worker_port] || frontend_port + 1
        end

        def backend_uri
          if inproc?
            "inproc://#{backend_ip}:#{backend_port}"
          else
            "tcp://#{backend_ip}:#{backend_port}"
          end
        end

        def beacon_interval
          [options[:beacon_interval].to_i, 1].max
        end

        def beacon_ip
          "255.255.255.255"
        end

        def beacon_port
          @beacon_port ||= options.fetch(
            :beacon_port,
            ::Protobuf::Rpc::ServiceDirectory.port,
          ).to_i
        end

        def beacon_uri
          "udp://#{beacon_ip}:#{beacon_port}"
        end

        def broadcast_beacons?
          !brokerless? && options[:broadcast_beacons]
        end

        def broadcast_busy?
          broadcast_beacons? && options[:broadcast_busy]
        end

        def broadcast_flatline
          flatline = ::Protobuf::Rpc::DynamicDiscovery::Beacon.new(
            :beacon_type => ::Protobuf::Rpc::DynamicDiscovery::BeaconType::FLATLINE,
            :server => to_proto,
          )

          @beacon_socket.send(flatline.encode, 0)
        end

        def broadcast_heartbeat
          @last_beacon = Time.now.to_i

          heartbeat = ::Protobuf::Rpc::DynamicDiscovery::Beacon.new(
            :beacon_type => ::Protobuf::Rpc::DynamicDiscovery::BeaconType::HEARTBEAT,
            :server => to_proto,
          )

          @beacon_socket.send(heartbeat.encode, 0)

          logger.debug { sign_message("sent heartbeat to #{beacon_uri}") }
        end

        def broadcast_heartbeat?
          Time.now.to_i >= next_beacon && broadcast_beacons?
        end

        def brokerless?
          !!options[:workers_only]
        end

        def busy_worker_count
          workers.count { |thread| !!thread[:busy] }
        end

        def frontend_ip
          @frontend_ip ||= resolve_ip(options[:host])
        end
        alias :backend_ip frontend_ip

        def frontend_port
          options[:port]
        end

        def frontend_uri
          "tcp://#{frontend_ip}:#{frontend_port}"
        end

        def inproc?
          !!options[:zmq_inproc]
        end

        def maintenance_timeout
          next_maintenance - Time.now.to_i
        end

        def next_maintenance
          cycles = [next_reaping]
          cycles << next_beacon if broadcast_beacons?

          cycles.min
        end

        def minimum_timeout
          0.1
        end

        def next_beacon
          if @last_beacon.nil?
            0
          else
            @last_beacon + beacon_interval
          end
        end

        def next_reaping
          if @last_reaping.nil?
            0
          else
            @last_reaping + reaping_interval
          end
        end

        def reap_dead_workers
          @last_reaping = Time.now.to_i

          @workers.keep_if do |worker|
            worker.alive? || worker.join && false
          end
        end

        def reap_dead_workers?
          Time.now.to_i >= next_reaping
        end

        def reaping_interval
          5
        end

        def run
          @running = true
          yield if block_given? # runs on startup
          wait_for_shutdown_signal
          broadcast_flatline if broadcast_beacons?
          Thread.pass until reap_dead_workers.empty?
          @broker_thread.join unless brokerless?
        ensure
          @running = false
          teardown
        end

        def running?
          !!@running
        end

        def start_missing_workers
          missing_workers = total_workers - @workers.size

          if missing_workers > 0
            missing_workers.times { start_worker }
            logger.debug { sign_message("#{total_workers} workers started") }
          end
        end

        def stop
          @running = false
          @shutdown_w.write('.')
        end

        def teardown
          @shutdown_r.try(:close)
          @shutdown_w.try(:close)
          @beacon_socket.try(:close)
          @zmq_context.try(:terminate)
          @last_reaping = @last_beacon = @timeout = nil
        end

        def timeout
          @timeout =
            if @timeout.nil?
              0
            else
              [minimum_timeout, maintenance_timeout].max
            end
        end

        def total_workers
          @total_workers ||= [@options[:threads].to_i, 1].max
        end

        def to_proto
          @proto ||= ::Protobuf::Rpc::DynamicDiscovery::Server.new(
            :uuid => uuid,
            :address => frontend_ip,
            :port => frontend_port.to_s,
            :ttl => (beacon_interval * 1.5).ceil,
            :services => ::Protobuf::Rpc::Service.implemented_services,
          )
        end

        def uuid
          @uuid ||= SecureRandom.uuid
        end

        def wait_for_shutdown_signal
          loop do
            break if IO.select([@shutdown_r], nil, nil, timeout)

            start_broker unless brokerless?
            reap_dead_workers if reap_dead_workers?
            start_missing_workers

            next unless broadcast_heartbeat?

            if broadcast_busy? && all_workers_busy?
              broadcast_flatline
            else
              broadcast_heartbeat
            end
          end
        end

        private

        def init_beacon_socket
          @beacon_socket = UDPSocket.new
          @beacon_socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_BROADCAST, true)
          @beacon_socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEADDR, true)

          if defined?(::Socket::SO_REUSEPORT)
            @beacon_socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, true)
          end

          @beacon_socket.bind(frontend_ip, beacon_port)
          @beacon_socket.connect(beacon_ip, beacon_port)
        end

        def init_shutdown_pipe
          @shutdown_r, @shutdown_w = IO.pipe
        end

        def init_zmq_context
          @zmq_context = ZMQ::Context.new
        end

        def start_broker
          return if @broker && @broker.running? && @broker_thread.alive?
          if @broker && !@broker.running?
            broadcast_flatline if broadcast_busy?
            @broker_thread.join if @broker_thread
            init_zmq_context # need a new context to restart the broker
          end

          @broker = ::Protobuf::Rpc::Zmq::Broker.new(self)
          @broker_thread = Thread.new(@broker) do |broker|
            begin
              broker.run
            rescue => e
              message = "Broker failed: #{e.inspect}\n #{e.backtrace.join($INPUT_RECORD_SEPARATOR)}"
              $stderr.puts(message)
              logger.error { message }
            end
          end
        end

        def start_worker
          @workers << Thread.new(self, @broker) do |server, broker|
            begin
              ::Protobuf::Rpc::Zmq::Worker.new(server, broker).run
            rescue => e
              message = "Worker failed: #{e.inspect}\n #{e.backtrace.join($INPUT_RECORD_SEPARATOR)}"
              $stderr.puts(message)
              logger.error { message }
            end
          end
        end
      end
    end
  end
end
