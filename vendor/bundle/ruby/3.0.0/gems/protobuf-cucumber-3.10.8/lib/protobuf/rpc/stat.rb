require 'date'
require 'time'
require 'protobuf/logging'
require 'protobuf/rpc/rpc.pb'

module Protobuf
  module Rpc
    class Stat
      attr_accessor :mode, :start_time, :end_time, :request_size, :dispatcher
      attr_accessor :response_size, :client, :service, :method_name, :status
      attr_reader   :server

      MODES = [:SERVER, :CLIENT].freeze

      ERROR_TRANSLATIONS = {
        ::Protobuf::Socketrpc::ErrorReason::BAD_REQUEST_DATA => "BAD_REQUEST_DATA",
        ::Protobuf::Socketrpc::ErrorReason::BAD_REQUEST_PROTO => "BAD_REQUEST_PROTO",
        ::Protobuf::Socketrpc::ErrorReason::SERVICE_NOT_FOUND => "SERVICE_NOT_FOUND",
        ::Protobuf::Socketrpc::ErrorReason::METHOD_NOT_FOUND => "METHOD_NOT_FOUND",
        ::Protobuf::Socketrpc::ErrorReason::RPC_ERROR => "RPC_ERROR",
        ::Protobuf::Socketrpc::ErrorReason::RPC_FAILED => "RPC_FAILED",
        ::Protobuf::Socketrpc::ErrorReason::INVALID_REQUEST_PROTO => "INVALID_REQUEST_PROTO",
        ::Protobuf::Socketrpc::ErrorReason::BAD_RESPONSE_PROTO => "BAD_RESPONSE_PROTO",
        ::Protobuf::Socketrpc::ErrorReason::UNKNOWN_HOST => "UNKNOWN_HOST",
        ::Protobuf::Socketrpc::ErrorReason::IO_ERROR => "IO_ERROR",
      }.freeze

      def initialize(mode = :SERVER)
        @mode = mode
        @request_size = 0
        @response_size = 0
        start
      end

      attr_writer :client

      def client
        @client || nil
      end

      def elapsed_time
        (start_time && end_time ? "#{(end_time - start_time).round(4)}s" : nil)
      end

      def method_name
        @method_name ||= @dispatcher.try(:service).try(:method_name)
      end

      def server=(peer)
        case peer
        when Array
          @server = "#{peer[1]}:#{peer[0]}"
        when String
          @server = peer
        end
      end

      def service
        @service ||= @dispatcher.try(:service).class.name
      end

      def sizes
        if stopped?
          "#{@request_size}B/#{@response_size}B"
        else
          "#{@request_size}B/-"
        end
      end

      def start
        @start_time ||= ::Time.now
      end

      def stop
        start unless @start_time
        @end_time ||= ::Time.now
      end

      def stopped?
        !end_time.nil?
      end

      def rpc
        service && method_name ? "#{service}##{method_name}" : nil
      end

      def server?
        @mode == :SERVER
      end

      def client?
        @mode == :CLIENT
      end

      def status_string
        return "OK" if status.nil?

        ERROR_TRANSLATIONS.fetch(status, "UNKNOWN_ERROR")
      end

      def to_s
        [
          server? ? "[SRV]" : "[CLT]",
          server? ? client : server,
          trace_id,
          rpc,
          sizes,
          elapsed_time,
          status_string,
          @end_time.try(:iso8601),
        ].compact.join(' - ')
      end

      def trace_id
        ::Thread.current.object_id.to_s(16)
      end
    end
  end
end
