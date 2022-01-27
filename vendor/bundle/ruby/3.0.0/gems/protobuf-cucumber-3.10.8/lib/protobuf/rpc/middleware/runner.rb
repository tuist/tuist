require 'middleware/runner'

module Protobuf
  module Rpc
    module Middleware
      class Runner < ::Middleware::Runner
        # Override the default middleware runner so we can ensure that the
        # service dispatcher is the last thing called in the stack.
        #
        def initialize(stack)
          stack << Protobuf::Rpc::ServiceDispatcher

          super(stack)
        end
      end
    end
  end
end
