require 'protobuf/rpc/rpc.pb'

module Protobuf
  module Rpc

    class BadRequestData < PbError
      def initialize(message = 'Unable to parse request')
        super message, 'BAD_REQUEST_DATA'
      end
    end

    class BadRequestProto < PbError
      def initialize(message = 'Request is of wrong type')
        super message, 'BAD_REQUEST_PROTO'
      end
    end

    class ServiceNotFound < PbError
      def initialize(message = 'Service class not found')
        super message, 'SERVICE_NOT_FOUND'
      end
    end

    class MethodNotFound < PbError
      def initialize(message = 'Service method not found')
        super message, 'METHOD_NOT_FOUND'
      end
    end

    class RpcError < PbError
      def initialize(message = 'RPC exception occurred')
        super message, 'RPC_ERROR'
      end
    end

    class RpcFailed < PbError
      def initialize(message = 'RPC failed')
        super message, 'RPC_FAILED'
      end
    end

  end
end
