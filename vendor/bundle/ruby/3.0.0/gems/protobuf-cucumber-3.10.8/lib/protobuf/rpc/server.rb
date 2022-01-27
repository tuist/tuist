require 'protobuf'
require 'protobuf/logging'
require 'protobuf/rpc/rpc.pb'
require 'protobuf/rpc/buffer'
require 'protobuf/rpc/env'
require 'protobuf/rpc/error'
require 'protobuf/rpc/middleware'
require 'protobuf/rpc/service_dispatcher'

module Protobuf
  module Rpc
    module Server
      def gc_pause
        ::GC.disable if ::Protobuf.gc_pause_server_request?

        yield

        ::GC.enable if ::Protobuf.gc_pause_server_request?
      end

      # Invoke the service method dictated by the proto wrapper request object
      #
      def handle_request(request_data, env_data = {})
        # Create an env object that holds different parts of the environment and
        # is available to all of the middlewares
        env = Env.new(env_data.merge('encoded_request' => request_data, 'log_signature' => log_signature))

        # Invoke the middleware stack, the last of which is the service dispatcher
        env = Rpc.middleware.call(env)

        env.encoded_response
      end

      def log_signature
        @_log_signature ||= "[server-#{self.class.name}]"
      end
    end
  end
end
