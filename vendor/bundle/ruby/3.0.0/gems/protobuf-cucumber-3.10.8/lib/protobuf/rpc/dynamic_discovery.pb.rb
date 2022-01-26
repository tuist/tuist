# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'

module Protobuf
  module Rpc
    module DynamicDiscovery
      ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

      ##
      # Enum Classes
      #
      class BeaconType < ::Protobuf::Enum
        define :HEARTBEAT, 0
        define :FLATLINE, 1
      end


      ##
      # Message Classes
      #
      class Server < ::Protobuf::Message; end
      class Beacon < ::Protobuf::Message; end


      ##
      # Message Fields
      #
      class Server
        optional :string, :uuid, 1
        optional :string, :address, 2
        optional :string, :port, 3
        optional :int32, :ttl, 4
        repeated :string, :services, 5
      end

      class Beacon
        optional ::Protobuf::Rpc::DynamicDiscovery::BeaconType, :beacon_type, 1
        optional ::Protobuf::Rpc::DynamicDiscovery::Server, :server, 2
      end

    end

  end

end

