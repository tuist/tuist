require 'protobuf/logging'
require 'protobuf/message'
require 'protobuf/rpc/client'
require 'protobuf/rpc/error'
require 'protobuf/rpc/rpc_method'
require 'protobuf/rpc/service_filters'

module Protobuf
  module Rpc
    # Object to encapsulate the request/response types for a given service method

    class Service
      include ::Protobuf::Logging
      include ::Protobuf::Rpc::ServiceFilters
      ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::ServiceOptions }

      DEFAULT_HOST = '127.0.0.1'.freeze
      DEFAULT_PORT = 9399

      attr_reader :env, :request

      ##
      # Constructor!
      #
      # Initialize a service with the rpc endpoint name and the bytes
      # for the request.
      def initialize(env)
        @env = env.dup # Dup the env so it doesn't change out from under us
        @request = env.request
      end

      ##
      # Class Methods
      #
      # Create a new client for the given service.
      # See Client#initialize and ClientConnection::DEFAULT_OPTIONS
      # for all available options.
      #
      def self.client(options = {})
        ::Protobuf::Rpc::Client.new({ :service => self,
                                      :host => host,
                                      :port => port }.merge(options))
      end

      # Allows service-level configuration of location.
      # Useful for system-startup configuration of a service
      # so that any Clients using the Service.client sugar
      # will not have to configure the location each time.
      #
      def self.configure(config = {})
        self.host = config[:host] if config.key?(:host)
        self.port = config[:port] if config.key?(:port)
      end

      # The host location of the service.
      #
      def self.host
        @host ||= DEFAULT_HOST
      end

      # The host location setter.
      #
      class << self
        attr_writer :host
      end

      # An array of defined service classes that contain implementation
      # code
      def self.implemented_services
        classes = (subclasses || []).select do |subclass|
          subclass.rpcs.any? do |(name, _)|
            subclass.method_defined? name
          end
        end

        classes.map(&:name)
      end

      # Shorthand call to configure, passing a string formatted as hostname:port
      # e.g. 127.0.0.1:9933
      # e.g. localhost:0
      #
      def self.located_at(location)
        return if location.nil? || location.downcase.strip !~ /.+:\d+/
        host, port = location.downcase.strip.split ':'
        configure(:host => host, :port => port.to_i)
      end

      # The port of the service on the destination server.
      #
      def self.port
        @port ||= DEFAULT_PORT
      end

      # The port location setter.
      #
      class << self
        attr_writer :port
      end

      # Define an rpc method with the given request and response types.
      # This methods is only used by the generated service definitions
      # and not useful for user code.
      #
      def self.rpc(method, request_type, response_type, &options_block)
        rpcs[method] = RpcMethod.new(method, request_type, response_type, &options_block)
      end

      # Hash containing the set of methods defined via `rpc`.
      #
      def self.rpcs
        @rpcs ||= {}
      end

      # Check if the given method name is a known rpc endpoint.
      #
      def self.rpc_method?(name)
        rpcs.key?(name)
      end

      def call(method_name)
        run_filters(method_name)
      end

      # Response object for this rpc cycle. Not assignable.
      #
      def response
        @response ||= response_type.new
      end

      # Convenience method to get back to class method.
      #
      def rpc_method?(name)
        self.class.rpc_method?(name)
      end

      # Convenience method to get back to class rpcs hash.
      #
      def rpcs
        self.class.rpcs
      end

      private

      def request_type
        @request_type ||= env.request_type
      end

      # Sugar to make an rpc method feel like a controller method.
      # If this method is not called, the response will be the memoized
      # object returned by the response reader.
      #
      def respond_with(candidate)
        @response = candidate
      end
      alias :return_from_whence_you_came respond_with

      def response_type
        @response_type ||= env.response_type
      end

      # Automatically fail a service method.
      #
      def rpc_failed(message)
        message = message.message if message.respond_to?(:message)
        fail RpcFailed, message
      end
    end

    ActiveSupport.run_load_hooks(:protobuf_rpc_service, Service)
  end
end
