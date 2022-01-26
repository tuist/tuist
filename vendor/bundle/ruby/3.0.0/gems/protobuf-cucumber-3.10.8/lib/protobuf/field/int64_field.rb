require 'protobuf/field/integer_field'

module Protobuf
  module Field
    class Int64Field < IntegerField

      ##
      # Class Methods
      #

      def self.max
        INT64_MAX
      end

      def self.min
        INT64_MIN
      end

      ##
      # Instance Methods
      #
      def acceptable?(val)
        if val.is_a?(Integer) || val.is_a?(Numeric)
          val >= INT64_MIN && val <= INT64_MAX
        else
          Integer(val, 10) >= INT64_MIN && Integer(val, 10) <= INT64_MAX
        end
      rescue
        return false
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
