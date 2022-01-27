require 'protobuf/logging'

module Protobuf
  module Rpc
    class ServiceDispatcher
      include ::Protobuf::Logging

      attr_reader :env

      def initialize(_app)
        # End of the line...
      end

      def call(env)
        dup._call(env)
      end

      def _call(env)
        @env = env

        env.response = dispatch_rpc_request
        env
      end

      def rpc_service
        @rpc_service ||= env.rpc_service.new(env)
      end

      private

      def dispatch_rpc_request
        rpc_service.call(method_name)
        rpc_service.response
      end

      def method_name
        env.method_name
      end

      def service_name
        env.service_name
      end
    end
  end
end
