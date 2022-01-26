require 'timeout'
require 'cucumber/wire/protocol'
require 'cucumber/wire/exception'
require 'cucumber/wire/data_packet'

module Cucumber
  module Wire
    class Connection
      class ConnectionError < StandardError; end

      include Wire::Protocol

      def initialize(config)
        @config = config
      end

      def call_remote(request_handler, message, params)
        packet = DataPacket.new(message, params)

        begin
          send_data_to_socket(packet.to_json)
          response = fetch_data_from_socket(@config.timeout(message))
          response.handle_with(request_handler)
        rescue Timeout::Error => e
          backtrace = e.backtrace ; backtrace.shift # because Timeout puts some wierd stuff in there
          raise Timeout::Error, "Timed out calling wire server with message '#{message}'", backtrace
        end
      end

      def exception(params)
        Wire::Exception.new(params, @config)
      end

      private

      def send_data_to_socket(data)
        Timeout.timeout(@config.timeout('connect')) { socket.puts(data) }
      end

      def fetch_data_from_socket(timeout)
        raw_response =
          if timeout == :never
            socket.gets
          else
            Timeout.timeout(timeout) { socket.gets }
          end
        raise exception({'message' => "Remote Socket with #{@config.host}:#{@config.port} closed."}) if raw_response.nil?
        DataPacket.parse(raw_response)
      end

      def socket
        return @socket if @socket
        if @config.unix
          @socket = UNIXSocket.new(@config.unix)
        else
          @socket = TCPSocket.new(@config.host, @config.port)
        end
      rescue Errno::ECONNREFUSED => exception
        raise(ConnectionError, "Unable to contact the wire server at #{@config}. Is it up?")
      end
    end
  end
end
