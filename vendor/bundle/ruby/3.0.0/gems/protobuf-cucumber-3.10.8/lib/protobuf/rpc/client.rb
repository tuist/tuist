require 'forwardable'
require 'protobuf'
require 'protobuf/logging'
require 'protobuf/rpc/error'

module Protobuf
  module Rpc
    class Client
      extend Forwardable
      include Protobuf::Logging

      def_delegators :@connector, :options, :complete_cb, :success_cb, :failure_cb, :send_request
      attr_reader :connector

      # Create a new client with default options (defined in ClientConnection)
      # See Service#client for a more convenient way to create a client, as well
      # as Client#method_missing defined below.
      #
      #   request = WidgetFindRequest.new
      #   client = Client.new({
      #     :service => WidgetService,
      #     :method => "find",
      #     :request_type => "WidgetFindRequest",
      #     :response_type => "WidgetList",
      #     :request => request
      #   })
      #
      def initialize(options = {})
        fail "Invalid client configuration. Service must be defined." if options[:service].nil?
        @connector = ::Protobuf.connector_type_class.new(options)
        logger.debug { sign_message("Initialized with options: #{options.inspect}") }
      end

      def log_signature
        @_log_signature ||= "[client-#{self.class}]"
      end

      # Set a complete callback on the client to return the object (self).
      #
      #   client = Client.new(:service => WidgetService)
      #   client.on_complete {|obj| ... }
      #
      def on_complete(&complete_cb)
        @connector.complete_cb = complete_cb
      end

      def on_complete=(callable)
        if !callable.nil? && !callable.respond_to?(:call) && callable.arity != 1
          fail "callable must take a single argument and respond to :call"
        end

        @connector.complete_cb = callable
      end

      # Set a failure callback on the client to return the
      # error returned by the service, if any. If this callback
      # is called, success_cb will NOT be called.
      #
      #   client = Client.new(:service => WidgetService)
      #   client.on_failure {|err| ... }
      #
      def on_failure(&failure_cb)
        @connector.failure_cb = failure_cb
      end

      def on_failure=(callable)
        if !callable.nil? && !callable.respond_to?(:call) && callable.arity != 1
          fail "Callable must take a single argument and respond to :call"
        end

        @connector.failure_cb = callable
      end

      # Set a success callback on the client to return the
      # successful response from the service when it is returned.
      # If this callback is called, failure_cb will NOT be called.
      #
      #   client = Client.new(:service => WidgetService)
      #   client.on_success {|res| ... }
      #
      def on_success(&success_cb)
        @connector.success_cb = success_cb
      end

      def on_success=(callable)
        if !callable.nil? && !callable.respond_to?(:call) && callable.arity != 1
          fail "Callable must take a single argument and respond to :call"
        end

        @connector.success_cb = callable
      end

      # Provides a mechanism to call the service method against the client
      # which will automatically setup the service_class and method_name
      # in the wrapper protobuf request.
      #
      #   # The :find method is not defined by Client which will trigger method_missing
      #   Client.new(:service => WidgetService).find do |c|
      #     # This block will be invoked before the request is made
      #     # `c` in this case is the client object you created above
      #     c.on_success {|res| ... }
      #     c.on_failure {|err| ... }
      #   end
      #
      def method_missing(method_name, *params)
        service = options[:service]
        if service.rpc_method?(method_name)
          logger.debug { sign_message("#{service.name}##{method_name}") }
          rpc = service.rpcs[method_name.to_sym]

          options[:request_type] = rpc.request_type
          logger.debug { sign_message("Request Type: #{options[:request_type].name}") }

          options[:response_type] = rpc.response_type
          logger.debug { sign_message("Response Type: #{options[:response_type].name}") }

          options[:method] = method_name.to_s
          options[:request] = params[0].is_a?(Hash) ? options[:request_type].new(params[0]) : params[0]
          logger.debug { sign_message("Request Data: #{options[:request].inspect}") }

          # Call client to setup on_success and on_failure event callbacks
          if block_given?
            logger.debug { sign_message("client setup callback given, invoking") }
            yield(self)
          else
            logger.debug { sign_message("no block given for callbacks") }
          end

          send_request
        else
          logger.error { sign_message("#{service.name}##{method_name} not rpc method, passing to super") }
          super(method_name, *params)
        end
      end

    end

    ActiveSupport.run_load_hooks(:protobuf_rpc_client, Client)
  end
end
