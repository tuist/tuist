require "thread_safe"
require "protobuf/rpc/connectors/base"
require "protobuf/rpc/connectors/ping"
require "protobuf/rpc/service_directory"

module Protobuf
  module Rpc
    module Connectors
      class Zmq < Base
        RequestTimeout = Class.new(RuntimeError)
        ZmqRecoverableError = Class.new(RuntimeError)
        ZmqEagainError = Class.new(RuntimeError)

        ##
        # Included Modules
        #
        include Protobuf::Logging

        ##
        # Class Constants
        #
        CLIENT_RETRIES = (ENV['PB_CLIENT_RETRIES'] || 3)

        ##
        # Class Methods
        #
        def self.ping_port_responses
          @ping_port_responses ||= ::ThreadSafe::Cache.new
        end

        def self.zmq_context(reload = false)
          @zmq_contexts = nil if reload
          @zmq_contexts ||= Hash.new do |hash, key|
            hash[key] = ZMQ::Context.new
          end

          @zmq_contexts[Process.pid]
        end

        ##
        # Instance methods
        #
        def log_signature
          @_log_signature ||= "[client-#{self.class}]"
        end

        # Start the request/response cycle. We implement the Lazy Pirate
        # req/reply reliability pattern as laid out in the ZMQ Guide, Chapter 4.
        #
        # @see http://zguide.zeromq.org/php:chapter4#Client-side-Reliability-Lazy-Pirate-Pattern
        #
        def send_request
          setup_connection
          send_request_with_lazy_pirate unless error?
        end

        private

        ##
        # Private Instance methods
        #
        def check_available_rcv_timeout
          @check_available_rcv_timeout ||= begin
            case
            when ENV.key?("PB_ZMQ_CLIENT_CHECK_AVAILABLE_RCV_TIMEOUT") then
              ENV["PB_ZMQ_CLIENT_CHECK_AVAILABLE_RCV_TIMEOUT"].to_i
            else
              200 # ms
            end
          end
        end

        def check_available_snd_timeout
          @check_available_snd_timeout ||= begin
            case
            when ENV.key?("PB_ZMQ_CLIENT_CHECK_AVAILABLE_SND_TIMEOUT") then
              ENV["PB_ZMQ_CLIENT_CHECK_AVAILABLE_SND_TIMEOUT"].to_i
            else
              200 # ms
            end
          end
        end

        def close_connection
          # The socket is automatically closed after every request.
        end

        # Create a socket connected to a server that can handle the current
        # service. The LINGER is set to 0 so we can close immediately in
        # the event of a timeout
        def create_socket
          attempt_number = 0

          begin
            attempt_number += 1
            socket = zmq_context.socket(::ZMQ::REQ)

            if socket # Make sure the context builds the socket
              server_uri = lookup_server_uri
              socket.setsockopt(::ZMQ::LINGER, 0)
              zmq_error_check(socket.connect(server_uri), :socket_connect)
              socket = socket_to_available_server(socket) if first_alive_load_balance?
            end
          end while socket.try(:socket).nil? && attempt_number < socket_creation_attempts

          raise RequestTimeout, "Cannot create new ZMQ client socket" if socket.try(:socket).nil?
          socket
        end

        # Method to determine error state, must be used with Connector API.
        #
        def error?
          !! @error
        end

        def host_alive?(host)
          return true unless ping_port_enabled?

          if (last_response = self.class.ping_port_responses[host])
            if (Time.now.to_i - last_response[:at]) <= host_alive_check_interval
              return last_response[:ping_port_open]
            end
          end

          ping_port_open = ping_port_open?(host)
          self.class.ping_port_responses[host] = {
            :at => Time.now.to_i,
            :ping_port_open => ping_port_open,
          }
          ping_port_open
        end

        def host_alive_check_interval
          @host_alive_check_interval ||= [ENV["PB_ZMQ_CLIENT_HOST_ALIVE_CHECK_INTERVAL"].to_i, 1].max
        end

        # Lookup a server uri for the requested service in the service
        # directory. If the service directory is not running, default
        # to the host and port in the options
        #
        def lookup_server_uri
          server_lookup_attempts.times do
            first_alive_listing = service_directory.all_listings_for(service).find do |listing|
              host_alive?(listing.try(:address))
            end

            if first_alive_listing
              host = first_alive_listing.try(:address)
              port = first_alive_listing.try(:port)
              @stats.server = [port, host]
              return "tcp://#{host}:#{port}"
            end

            host = options[:host]
            port = options[:port]

            if host_alive?(host)
              @stats.server = [port, host]
              return "tcp://#{host}:#{port}"
            end

            sleep(1.0 / 100.0)
          end

          fail "Host not found for service #{service}"
        end

        def ping_port_open?(host)
          Ping.new(host, ping_port.to_i).online?
        end

        def rcv_timeout
          @rcv_timeout ||= begin
            case
            when options[:timeout] then
              options[:timeout]
            when ENV.key?("PB_ZMQ_CLIENT_RCV_TIMEOUT") then
              ENV["PB_ZMQ_CLIENT_RCV_TIMEOUT"].to_i
            else
              300_000 # 300 seconds
            end
          end
        end

        # Trying a number of times, attempt to get a response from the server.
        # If we haven't received a legitimate response in the CLIENT_RETRIES number
        # of retries, fail the request.
        #
        def send_request_with_lazy_pirate
          attempt = 0

          begin
            attempt += 1
            send_request_with_timeout(attempt)
            parse_response
          rescue RequestTimeout
            retry if attempt < CLIENT_RETRIES
            failure(:RPC_FAILED, "The server repeatedly failed to respond within #{timeout} seconds")
          end
        end

        def send_request_with_timeout(attempt = 0)
          socket = create_socket
          socket.setsockopt(::ZMQ::RCVTIMEO, rcv_timeout)
          socket.setsockopt(::ZMQ::SNDTIMEO, snd_timeout)

          logger.debug { sign_message("Sending Request (attempt #{attempt}, #{socket})") }
          zmq_eagain_error_check(socket.send_string(@request_data), :socket_send_string)
          logger.debug { sign_message("Waiting #{rcv_timeout}ms for response (attempt #{attempt}, #{socket})") }
          zmq_eagain_error_check(socket.recv_string(@response_data = ""), :socket_recv_string)
          logger.debug { sign_message("Response received (attempt #{attempt}, #{socket})") }
        rescue ZmqEagainError
          logger.debug { sign_message("Timed out waiting for response (attempt #{attempt}, #{socket})") }
          raise RequestTimeout
        ensure
          logger.debug { sign_message("Closing Socket") }
          zmq_error_check(socket.close, :socket_close) if socket
          logger.debug { sign_message("Socket closed") }
        end

        def server_lookup_attempts
          @server_lookup_attempts ||= [ENV["PB_ZMQ_CLIENT_SERVER_LOOKUP_ATTEMPTS"].to_i, 5].max
        end

        # The service we're attempting to connect to
        #
        def service
          options[:service]
        end

        # Alias for ::Protobuf::Rpc::ServiceDirectory.instance
        def service_directory
          ::Protobuf::Rpc.service_directory
        end

        def snd_timeout
          @snd_timeout ||= begin
            case
            when options[:timeout] then
              options[:timeout]
            when ENV.key?("PB_ZMQ_CLIENT_SND_TIMEOUT") then
              ENV["PB_ZMQ_CLIENT_SND_TIMEOUT"].to_i
            else
              300_000 # 300 seconds
            end
          end
        end

        def socket_creation_attempts
          @socket_creation_attempts ||= (ENV["PB_ZMQ_CLIENT_SOCKET_CREATION_ATTEMPTS"] || 5).to_i
        end

        def socket_to_available_server(socket)
          check_available_response = ""
          socket.setsockopt(::ZMQ::RCVTIMEO, check_available_rcv_timeout)
          socket.setsockopt(::ZMQ::SNDTIMEO, check_available_snd_timeout)
          zmq_recoverable_error_check(socket.send_string(::Protobuf::Rpc::Zmq::CHECK_AVAILABLE_MESSAGE), :socket_send_string)
          zmq_recoverable_error_check(socket.recv_string(check_available_response), :socket_recv_string)

          if check_available_response == ::Protobuf::Rpc::Zmq::NO_WORKERS_AVAILABLE
            zmq_recoverable_error_check(socket.close, :socket_close)
          end

          socket.setsockopt(::ZMQ::RCVTIMEO, -1)
          socket.setsockopt(::ZMQ::SNDTIMEO, -1)
          socket
        rescue ZmqRecoverableError
          return nil # couldn't make a connection and need to try again
        end

        # Return the ZMQ Context to use for this process.
        # If the context does not exist, create it, then register
        # an exit block to ensure the context is terminated correctly.
        #
        def zmq_context(reload = false)
          self.class.zmq_context(reload)
        end

        def zmq_eagain_error_check(return_code, source)
          return if ::ZMQ::Util.resultcode_ok?(return_code || -1)

          if ::ZMQ::Util.errno == ::ZMQ::EAGAIN # rubocop:disable Style/GuardClause
            fail ZmqEagainError, <<-ERROR
            Last ZMQ API call to #{source} failed with "#{::ZMQ::Util.error_string}".

            #{caller(1).join($INPUT_RECORD_SEPARATOR)}
            ERROR
          else
            fail <<-ERROR
            Last ZMQ API call to #{source} failed with "#{::ZMQ::Util.error_string}".

            #{caller(1).join($INPUT_RECORD_SEPARATOR)}
            ERROR
          end
        end

        def zmq_error_check(return_code, source)
          return if ::ZMQ::Util.resultcode_ok?(return_code || -1)

          fail <<-ERROR
          Last ZMQ API call to #{source} failed with "#{::ZMQ::Util.error_string}".

          #{caller(1).join($INPUT_RECORD_SEPARATOR)}
          ERROR
        end

        def zmq_recoverable_error_check(return_code, source)
          return if ::ZMQ::Util.resultcode_ok?(return_code || -1)

          fail ZmqRecoverableError, <<-ERROR
          Last ZMQ API call to #{source} failed with "#{::ZMQ::Util.error_string}".

          #{caller(1).join($INPUT_RECORD_SEPARATOR)}
          ERROR
        end
      end
    end
  end
end
