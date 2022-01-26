module Protobuf
  module Rpc
    module Middleware
      class ExceptionHandler
        include ::Protobuf::Logging

        attr_reader :app

        def initialize(app)
          @app = app
        end

        def call(env)
          dup._call(env)
        end

        def _call(env)
          app.call(env)
        rescue => exception
          log_exception(exception)

          # Rescue exceptions, re-wrap them as generic Protobuf errors,
          # and encode them
          env.response = wrap_exception(exception)
          env.encoded_response = env.response.encode
          env
        end

        private

        # Wrap exceptions in a generic Protobuf errors unless they already are
        #
        def wrap_exception(exception)
          exception = RpcFailed.new(exception.message) unless exception.is_a?(PbError)
          exception
        end
      end
    end
  end
end
