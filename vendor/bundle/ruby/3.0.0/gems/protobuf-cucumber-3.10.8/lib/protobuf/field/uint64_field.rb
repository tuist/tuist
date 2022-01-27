require 'protobuf/field/varint_field'

module Protobuf
  module Field
    class Uint64Field < VarintField

      ##
      # Class Methods
      #

      def self.max
        UINT64_MAX
      end

      def self.min
        0
      end

      def json_encode(value, options = {})
        if options[:proto3]
          value == 0 ? nil : value.to_s
        else
          value
        end
      end
    end
  end
end
