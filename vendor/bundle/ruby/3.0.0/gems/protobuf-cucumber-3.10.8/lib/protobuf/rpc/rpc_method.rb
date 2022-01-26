module Protobuf
  module Rpc
    class RpcMethod
      ::Protobuf::Optionable.inject(self, false) { ::Google::Protobuf::MethodOptions }

      attr_reader :method, :request_type, :response_type

      def initialize(method, request_type, response_type, &options_block)
        @method = method
        @request_type = request_type
        @response_type = response_type
        instance_eval(&options_block) if options_block
      end
    end
  end
end
