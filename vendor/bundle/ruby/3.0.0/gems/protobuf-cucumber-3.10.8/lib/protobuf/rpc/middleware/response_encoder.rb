module Protobuf
  module Rpc
    module Middleware
      class ResponseEncoder
        include ::Protobuf::Logging

        attr_reader :app, :env

        def initialize(app)
          @app = app
        end

        def call(env)
          dup._call(env)
        end

        def _call(env)
          @env = app.call(env)

          env.response = response
          env.encoded_response = encoded_response
          env
        end

        def log_signature
          env.log_signature || super
        end

        private

        # Encode the response wrapper to return to the client
        #
        def encoded_response
          logger.debug { sign_message("Encoding response: #{response.inspect}") }

          env.encoded_response = wrapped_response.encode
        rescue => exception
          log_exception(exception)

          # Rescue encoding exceptions, re-wrap them as generic protobuf errors,
          # and re-raise them
          raise PbError, exception.message
        end

        # Prod the object to see if we can produce a proto object as a response
        # candidate. Validate the candidate protos.
        def response
          return @response unless @response.nil?

          candidate = env.response
          return @response = validate!(candidate) if candidate.is_a?(Message)
          return @response = validate!(candidate.to_proto) if candidate.respond_to?(:to_proto)
          return @response = env.response_type.new(candidate.to_hash) if candidate.respond_to?(:to_hash)
          return @response = candidate if candidate.is_a?(PbError)

          @response = validate!(candidate)
        end

        # Ensure that the response candidate we've been given is of the type
        # we expect so that deserialization on the client side works.
        #
        def validate!(candidate)
          if candidate.class != env.response_type
            fail BadResponseProto, "Expected response to be of type #{env.response_type.name} but was #{candidate.class.name}"
          end

          candidate
        end

        # The middleware stack returns either an error or response proto. Package
        # it up so that it's in the correct spot in the response wrapper
        #
        def wrapped_response
          if response.is_a?(::Protobuf::Rpc::PbError)
            ::Protobuf::Socketrpc::Response.new(:error => response.message, :error_reason => response.error_type, :server => env.server)
          else
            ::Protobuf::Socketrpc::Response.new(:response_proto => response.encode, :server => env.server)
          end
        end
      end
    end
  end
end
