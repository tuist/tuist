require 'protobuf/field/signed_integer_field'

module Protobuf
  module Field
    class Sint32Field < SignedIntegerField

      ##
      # Class Methods
      #

      def self.max
        INT32_MAX
      end

      def self.min
        INT32_MIN
      end

    end
  end
end
