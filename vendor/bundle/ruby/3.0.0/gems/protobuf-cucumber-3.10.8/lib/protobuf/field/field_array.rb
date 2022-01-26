module Protobuf
  module Field
    class FieldArray < Array

      ##
      # Attributes
      #

      attr_reader :field

      ##
      # Constructor
      #

      def initialize(field)
        @field = field
      end

      ##
      # Public Instance Methods
      #

      def []=(nth, val)
        super(nth, normalize(val)) unless val.nil?
      end

      def <<(val)
        super(normalize(val)) unless val.nil?
      end

      def push(val)
        super(normalize(val)) unless val.nil?
      end

      def replace(val)
        raise_type_error(val) unless val.is_a?(Array)
        val.map! { |v| normalize(v) }
        super(val)
      end

      # Return a hash-representation of the given values for this field type.
      # The value in this case would be an array.
      def to_hash_value
        map do |value|
          value.respond_to?(:to_hash_value) ? value.to_hash_value : value
        end
      end

      # Return a hash-representation of the given values for this field type
      # that is safe to convert to JSON.
      # The value in this case would be an array.
      def to_json_hash_value(options = {})
        if field.respond_to?(:json_encode)
          map do |value|
            field.json_encode(value)
          end
        else
          map do |value|
            value.respond_to?(:to_json_hash_value) ? value.to_json_hash_value(options) : value
          end
        end
      end

      def to_s
        "[#{field.name}]"
      end

      def unshift(val)
        super(normalize(val)) unless val.nil?
      end

      private

      ##
      # Private Instance Methods
      #

      def normalize(value)
        value = value.to_proto if value.respond_to?(:to_proto)
        fail TypeError, "Unacceptable value #{value} for field #{field.name} of type #{field.type_class}" unless field.acceptable?(value)

        if field.is_a?(::Protobuf::Field::EnumField)
          field.type_class.fetch(value)
        elsif field.is_a?(::Protobuf::Field::BytesField)
          field.coerce!(value)
        elsif field.is_a?(::Protobuf::Field::MessageField) && value.is_a?(field.type_class)
          value
        elsif field.is_a?(::Protobuf::Field::MessageField) && value.respond_to?(:to_hash)
          field.type_class.new(value.to_hash)
        else
          value
        end
      end

      def raise_type_error(val)
        fail TypeError, <<-TYPE_ERROR
          Expected repeated value of type '#{field.type_class}'
          Got '#{val.class}' for repeated protobuf field #{field.name}
        TYPE_ERROR
      end

    end
  end
end
