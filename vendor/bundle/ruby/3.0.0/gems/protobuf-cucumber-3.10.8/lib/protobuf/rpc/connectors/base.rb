require 'timeout'
require 'protobuf/logging'
require 'protobuf/rpc/rpc.pb'
require 'protobuf/rpc/buffer'
require 'protobuf/rpc/error'
require 'protobuf/rpc/stat'

module Protobuf
  module Rpc
    module Connectors
      DEFAULT_OPTIONS = {
        :service                 => nil,         # Fully-qualified Service class
        :method                  => nil,         # Service method to invoke
        :host                    => '127.0.0.1', # The hostname or address of the service (usually overridden)
        :port                    => '9399',      # The port of the service (usually overridden or pre-configured)
        :request                 => nil,         # The request object sent by the client
        :request_type            => nil,         # The request type expected by the client
        :response_type           => nil,         # The response type expected by the client
        :timeout                 => nil,         # The timeout for the request, also handled by client.rb
        :client_host             => nil,         # The hostname or address of this client
        :first_alive_load_balance => false,      # Do we want to use check_avail frames before request
      }.freeze

      class Base
        include Protobuf::Logging

        attr_reader :options, :error
        attr_accessor :success_cb, :failure_cb, :complete_cb, :stats

        def initialize(options)
          @options = DEFAULT_OPTIONS.merge(options)
          @stats = ::Protobuf::Rpc::Stat.new(:CLIENT)
        end

        def any_callbacks?
          [@complete_cb, @failure_cb, @success_cb].any?
        end

        def close_connection
          fail 'If you inherit a Connector from Base you must implement close_connection'
        end

        def complete
          @stats.stop
          logger.info { @stats.to_s }
          logger.debug { sign_message('Response proceessing complete') }
          @complete_cb.call(self) unless @complete_cb.nil?
        rescue => e
          logger.error { sign_message('Complete callback error encountered') }
          log_exception(e)
          raise
        end

        def data_callback(data)
          logger.debug { sign_message('Using data_callback') }
          @used_data_callback = true
          @data = data
        end

        # All failures should be routed through this method.
        #
        # @param [Symbol] code The code we're using (see ::Protobuf::Socketrpc::ErrorReason)
        # @param [String] message The error message
        def failure(code, message)
          @error = ClientError.new
          @stats.status = @error.code = ::Protobuf::Socketrpc::ErrorReason.fetch(code)
          @error.message = message

          logger.debug { sign_message("Server failed request (invoking on_failure): #{@error.inspect}") }

          @failure_cb.call(@error) unless @failure_cb.nil?
        rescue => e
          logger.error { sign_message("Failure callback error encountered") }
          log_exception(e)
          raise
        ensure
          complete
        end

        def first_alive_load_balance?
          ENV.key?("PB_FIRST_ALIVE_LOAD_BALANCE") ||
            options[:first_alive_load_balance]
        end

        def initialize_stats
          @stats = ::Protobuf::Rpc::Stat.new(:CLIENT)
          @stats.server = [@options[:port], @options[:host]]
          @stats.service = @options[:service].name
          @stats.method_name = @options[:method].to_s
        rescue => ex
          log_exception(ex)
          failure(:RPC_ERROR, "Invalid stats configuration. #{ex.message}")
        end

        def log_signature
          @_log_signature ||= "[client-#{self.class}]"
        end

        def parse_response
          # Close up the connection as we no longer need it
          close_connection

          logger.debug { sign_message("Parsing response from server (connection closed)") }

          # Parse out the raw response
          @stats.response_size = @response_data.size unless @response_data.nil?
          response_wrapper = ::Protobuf::Socketrpc::Response.decode(@response_data)
          @stats.server = response_wrapper.server if response_wrapper.field?(:server)

          # Determine success or failure based on parsed data
          if response_wrapper.field?(:error_reason)
            logger.debug { sign_message("Error response parsed") }

            # fail the call if we already know the client is failed
            # (don't try to parse out the response payload)
            failure(response_wrapper.error_reason, response_wrapper.error)
          else
            logger.debug { sign_message("Successful response parsed") }

            # Ensure client_response is an instance
            parsed = @options[:response_type].decode(response_wrapper.response_proto.to_s)

            if parsed.nil? && !response_wrapper.field?(:error_reason)
              failure(:BAD_RESPONSE_PROTO, 'Unable to parse response from server')
            else
              verify_callbacks
              succeed(parsed)
              return @data if @used_data_callback
            end
          end
        end

        def ping_port
          @ping_port ||= ENV["PB_RPC_PING_PORT"]
        end

        def ping_port_enabled?
          ENV.key?("PB_RPC_PING_PORT")
        end

        def request_bytes
          validate_request_type!
          return ::Protobuf::Socketrpc::Request.encode(request_fields)
        rescue => e
          failure(:INVALID_REQUEST_PROTO, "Could not set request proto: #{e.message}")
        end

        def request_caller
          @options[:client_host] || ::Protobuf.client_host
        end

        def request_fields
          { :service_name => @options[:service].name,
            :method_name => @options[:method].to_s,
            :request_proto => @options[:request],
            :caller => request_caller }
        end

        def send_request
          fail 'If you inherit a Connector from Base you must implement send_request'
        end

        def setup_connection
          initialize_stats
          @request_data = request_bytes
          @stats.request_size = @request_data.size
        end

        def succeed(response)
          logger.debug { sign_message("Server succeeded request (invoking on_success)") }
          @success_cb.call(response) unless @success_cb.nil?
        rescue => e
          logger.error { sign_message("Success callback error encountered") }
          log_exception(e)
          failure(:RPC_ERROR, "An exception occurred while calling on_success: #{e.message}")
        ensure
          complete
        end

        def timeout
          if options[:timeout]
            options[:timeout]
          else
            300 # seconds
          end
        end

        # Wrap the given block in a timeout of the configured number of seconds.
        #
        def timeout_wrap(&block)
          ::Timeout.timeout(timeout, &block)
        rescue ::Timeout::Error
          failure(:RPC_FAILED, "The server took longer than #{timeout} seconds to respond")
        end

        def validate_request_type!
          unless @options[:request].class == @options[:request_type]
            expected = @options[:request_type].name
            actual = @options[:request].class.name
            failure(:INVALID_REQUEST_PROTO, "Expected request type to be type of #{expected}, got #{actual} instead")
          end
        end

        def verify_callbacks
          unless any_callbacks?
            logger.debug { sign_message("No callbacks set, using data_callback") }
            @success_cb = @failure_cb = method(:data_callback)
          end
        end

        def verify_options!
          # Verify the options that are necessary and merge them in
          [:service, :method, :host, :port].each do |opt|
            failure(:RPC_ERROR, "Invalid client connection configuration. #{opt} must be a defined option.") if @options[opt].nil?
          end
        end

      end
    end
  end
end
