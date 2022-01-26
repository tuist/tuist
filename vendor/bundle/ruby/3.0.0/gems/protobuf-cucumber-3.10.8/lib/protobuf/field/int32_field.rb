require 'protobuf/field/integer_field'

module Protobuf
  module Field
    class Int32Field < IntegerField

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
