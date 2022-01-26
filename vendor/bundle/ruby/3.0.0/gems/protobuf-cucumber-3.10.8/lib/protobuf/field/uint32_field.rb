require 'protobuf/field/varint_field'

module Protobuf
  module Field
    class Uint32Field < VarintField

      ##
      # Class Methods
      #

      def self.max
        UINT32_MAX
      end

      def self.min
        0
      end

    end
  end
end
