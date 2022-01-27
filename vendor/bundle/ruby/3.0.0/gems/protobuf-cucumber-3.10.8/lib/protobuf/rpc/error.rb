require 'protobuf/rpc/rpc.pb'

module Protobuf
  module Rpc
    ClientError = Struct.new("ClientError", :code, :message)

    # Base PbError class for client and server errors
    class PbError < StandardError
      attr_reader :error_type

      def initialize(message = 'An unknown RpcError occurred', error_type = 'RPC_ERROR')
        @error_type = error_type.is_a?(String) ? ::Protobuf::Socketrpc::ErrorReason.const_get(error_type) : error_type
        super message
      end

      def encode
        to_response.encode
      end

      def to_response
        ::Protobuf::Socketrpc::Response.new(:error => message, :error_reason => error_type)
      end
    end
  end
end

require 'protobuf/rpc/error/server_error'
require 'protobuf/rpc/error/client_error'
