# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Protobuf
  module Socketrpc
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

    ##
    # Enum Classes
    #
    class ErrorReason < ::Protobuf::Enum
      define :BAD_REQUEST_DATA, 0
      define :BAD_REQUEST_PROTO, 1
      define :SERVICE_NOT_FOUND, 2
      define :METHOD_NOT_FOUND, 3
      define :RPC_ERROR, 4
      define :RPC_FAILED, 5
      define :INVALID_REQUEST_PROTO, 6
      define :BAD_RESPONSE_PROTO, 7
      define :UNKNOWN_HOST, 8
      define :IO_ERROR, 9
    end


    ##
    # Message Classes
    #
    class Request < ::Protobuf::Message; end
    class Response < ::Protobuf::Message; end
    class Header < ::Protobuf::Message; end


    ##
    # Message Fields
    #
    class Request
      required :string, :service_name, 1
      required :string, :method_name, 2
      optional :bytes, :request_proto, 3
      optional :string, :caller, 4
      repeated ::Protobuf::Socketrpc::Header, :headers, 5
    end

    class Response
      optional :bytes, :response_proto, 1
      optional :string, :error, 2
      optional :bool, :callback, 3, :default => false
      optional ::Protobuf::Socketrpc::ErrorReason, :error_reason, 4
      optional :string, :server, 5
    end

    class Header
      required :string, :key, 1
      optional :string, :value, 2
    end

  end

end

