module Protobuf
  module Rpc
    class SocketRunner

      private

      attr_accessor :server

      public

      def initialize(options)
        options = case
                  when options.is_a?(OpenStruct) then
                    options.marshal_dump
                  when options.respond_to?(:to_hash) then
                    options.to_hash.symbolize_keys
                  else
                    fail "Cannot parser Socket Server - server options"
                  end

        self.server = ::Protobuf::Rpc::Socket::Server.new(options)
      end

      def run
        yield if block_given?
        server.run
      end

      def running?
        server.running?
      end

      def stop
        server.stop
      end
    end
  end
end

module Protobuf
  module Rpc
    module Servers # bad file namespacing
      SocketRunner = ::Protobuf::Rpc::SocketRunner
    end
  end
end
