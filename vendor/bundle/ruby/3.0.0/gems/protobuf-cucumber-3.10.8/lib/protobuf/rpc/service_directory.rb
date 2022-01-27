require 'delegate'
require 'singleton'
require 'socket'
require 'set'
require 'thread'
require 'timeout'

require 'protobuf/rpc/dynamic_discovery.pb'

module Protobuf
  module Rpc
    def self.service_directory
      @service_directory ||= ::Protobuf::Rpc::ServiceDirectory.instance
    end

    def self.service_directory=(directory)
      @service_directory = directory
    end

    class ServiceDirectory
      include ::Singleton
      include ::Protobuf::Logging

      DEFAULT_ADDRESS = '0.0.0.0'.freeze
      DEFAULT_PORT = 53000
      DEFAULT_TIMEOUT = 1

      class Listing < SimpleDelegator
        attr_reader :expires_at

        def initialize(server)
          update(server)
        end

        def current?
          !expired?
        end

        def eql?(other)
          uuid.eql?(other.uuid)
        end

        def expired?
          Time.now.to_i >= @expires_at
        end

        def hash
          uuid.hash
        end

        def ttl
          [super.to_i, 1].max
        end

        def update(server)
          __setobj__(server)
          @expires_at = Time.now.to_i + ttl
        end
      end

      # Class Methods
      #
      class << self
        attr_writer :address, :port
      end

      def self.address
        @address ||= DEFAULT_ADDRESS
      end

      def self.port
        @port ||= DEFAULT_PORT
      end

      def self.start
        yield(self) if block_given?
        instance.start
      end

      def self.stop
        instance.stop
      end

      #
      # Instance Methods
      #
      def initialize
        reset
      end

      def all_listings_for(service)
        if running? && @listings_by_service.key?(service.to_s)
          start_listener_thread if listener_dead?
          @listings_by_service[service.to_s].entries.shuffle
        else
          []
        end
      end

      def each_listing(&block)
        start_listener_thread if listener_dead?
        @listings_by_uuid.each_value(&block)
      end

      def lookup(service)
        return unless running?
        start_listener_thread if listener_dead?
        return unless @listings_by_service.key?(service.to_s)
        @listings_by_service[service.to_s].entries.sample
      end

      def listener_dead?
        @thread.nil? || !@thread.alive?
      end

      def restart
        stop
        start
      end

      def running?
        !!@running
      end

      def start
        unless running?
          init_socket
          logger.info { sign_message("listening to udp://#{self.class.address}:#{self.class.port}") }
          @running = true
        end

        start_listener_thread if listener_dead?
        self
      end

      def start_listener_thread
        return if @thread.try(:alive?)
        @thread = Thread.new { send(:run) }
      end

      def stop
        logger.info { sign_message("Stopping directory") }

        @running = false
        @thread.try(:kill).try(:join)
        @socket.try(:close)

        reset
      end

      private

      def add_or_update_listing(uuid, server)
        listing = @listings_by_uuid[uuid]

        if listing
          action = :updated
          listing.update(server)
        else
          action = :added
          listing = Listing.new(server)
          @listings_by_uuid[uuid] = listing
        end

        listing.services.each do |service|
          @listings_by_service[service] << listing
        end

        trigger(action, listing)
        logger.debug { sign_message("#{action} server: #{server.inspect}") }
      end

      def init_socket
        @socket = UDPSocket.new
        @socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEADDR, true)

        if defined?(::Socket::SO_REUSEPORT)
          @socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_REUSEPORT, true)
        end

        @socket.bind(self.class.address, self.class.port.to_i)
      end

      def process_beacon(beacon)
        server = beacon.server
        uuid = server.try(:uuid)

        if server && uuid
          case beacon.beacon_type
          when ::Protobuf::Rpc::DynamicDiscovery::BeaconType::HEARTBEAT
            add_or_update_listing(uuid, server)
          when ::Protobuf::Rpc::DynamicDiscovery::BeaconType::FLATLINE
            remove_listing(uuid)
          end
        else
          logger.info { sign_message("Ignoring incomplete beacon: #{beacon.inspect}") }
        end
      end

      def read_beacon
        data, addr = @socket.recvfrom(2048)

        beacon = ::Protobuf::Rpc::DynamicDiscovery::Beacon.decode(data)

        # Favor the address captured by the socket
        beacon.try(:server).try(:address=, addr[3])

        beacon
      end

      def remove_expired_listings
        logger.debug { sign_message("Removing expired listings") }
        @listings_by_uuid.each do |uuid, listing|
          remove_listing(uuid) if listing.expired?
        end
      end

      def remove_listing(uuid)
        listing = @listings_by_uuid[uuid] || return

        logger.debug { sign_message("Removing listing: #{listing.inspect}") }

        @listings_by_service.each_value do |listings|
          listings.delete(listing)
        end

        trigger(:removed, @listings_by_uuid.delete(uuid))
      end

      def reset
        @thread = nil
        @socket = nil
        @listings_by_uuid = {}
        @listings_by_service = Hash.new { |h, k| h[k] = Set.new }
      end

      def run
        sweep_interval = 5 # sweep expired listings every 5 seconds
        next_sweep = Time.now.to_i + sweep_interval

        loop do
          timeout = [next_sweep - Time.now.to_i, 0.1].max
          readable = IO.select([@socket], nil, nil, timeout)
          process_beacon(read_beacon) if readable

          if Time.now.to_i >= next_sweep
            remove_expired_listings
            next_sweep = Time.now.to_i + sweep_interval
          end
        end
      rescue => e
        logger.debug { sign_message("ERROR: (#{e.class}) #{e.message}\n#{e.backtrace.join("\n")}") }
        retry
      end

      def trigger(action, listing)
        ::ActiveSupport::Notifications.instrument("directory.listing.#{action}", :listing => listing)
      end
    end
  end
end
