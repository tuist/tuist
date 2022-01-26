require 'protobuf/field/varint_field'

module Protobuf
  module Field
    class SignedIntegerField < VarintField

      ##
      # Public Instance Methods
      #

      def decode(value)
        if (value & 1).zero?
          value >> 1   # positive value
        else
          ~value >> 1  # negative value
        end
      end

      def encode(value)
        if value >= 0
          VarintField.encode(value << 1)
        else
          VarintField.encode(~(value << 1))
        end
      end

    end
  end
end
