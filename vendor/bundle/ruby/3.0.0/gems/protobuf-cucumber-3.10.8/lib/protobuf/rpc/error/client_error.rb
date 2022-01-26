require 'protobuf/rpc/error'

module Protobuf
  module Rpc

    class InvalidRequestProto < PbError
      def initialize(message = 'Invalid request type given')
        super message, 'INVALID_REQUEST_PROTO'
      end
    end

    class BadResponseProto < PbError
      def initialize(message = 'Bad response type from server')
        super message, 'BAD_RESPONSE_PROTO'
      end
    end

    class UnkownHost < PbError
      def initialize(message = 'Unknown host or port')
        super message, 'UNKNOWN_HOST'
      end
    end

    class IOError < PbError
      def initialize(message = 'IO Error occurred')
        super message, 'IO_ERROR'
      end
    end

  end
end
