require 'ostruct'
require 'thread'

module Protobuf
  module Rpc
    class ZmqRunner
      include ::Protobuf::Logging

      def initialize(options)
        @options = case
                   when options.is_a?(OpenStruct) then
                     options.marshal_dump
                   when options.respond_to?(:to_hash) then
                     options.to_hash.symbolize_keys
                   else
                     fail "Cannot parser Zmq Server - server options"
                   end
      end

      def run
        @server = ::Protobuf::Rpc::Zmq::Server.new(@options)
        register_signals
        @server.run do
          yield if block_given?
        end
      end

      def running?
        @server.try :running?
      end

      def stop
        @server.try :stop
      end

      private

      def register_signals
        trap(:TRAP) do
          ::Thread.list.each do |thread|
            logger.info do
              <<-THREAD_TRACE
                #{thread.inspect}:
                  #{thread.backtrace.try(:join, $INPUT_RECORD_SEPARATOR)}"
              THREAD_TRACE
            end
          end
        end

        trap(:TTIN) do
          @server.add_worker
          logger.info { "Increased worker size to: #{@server.total_workers}" }
        end

        trap(:TTOU) do
          logger.info { "Current worker size: #{@server.workers.size}" }
          logger.info { "Current busy worker size: #{@server.busy_worker_count}" }
        end
      end
    end
  end
end

module Protobuf
  module Rpc
    module Servers # bad file namespacing
      ZmqRunner = ::Protobuf::Rpc::ZmqRunner
    end
  end
end
