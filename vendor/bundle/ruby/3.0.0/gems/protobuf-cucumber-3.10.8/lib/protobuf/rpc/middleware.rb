require 'middleware'

require 'protobuf/rpc/middleware/exception_handler'
require 'protobuf/rpc/middleware/logger'
require 'protobuf/rpc/middleware/request_decoder'
require 'protobuf/rpc/middleware/response_encoder'
require 'protobuf/rpc/middleware/runner'

module Protobuf
  module Rpc
    def self.middleware
      @middleware ||= ::Middleware::Builder.new(:runner_class => ::Protobuf::Rpc::Middleware::Runner)
    end

    # Ensure the middleware stack is initialized
    middleware
  end

  Rpc.middleware.use(Rpc::Middleware::ExceptionHandler)
  Rpc.middleware.use(Rpc::Middleware::RequestDecoder)
  Rpc.middleware.use(Rpc::Middleware::Logger)
  Rpc.middleware.use(Rpc::Middleware::ResponseEncoder)

  ActiveSupport.run_load_hooks(:protobuf_rpc_middleware, Rpc)
end
