require 'active_support/core_ext/hash/slice'
require 'protobuf/field/field_array'
require 'protobuf/field/field_hash'
require 'protobuf/field/base_field_object_definitions'

module Protobuf
  module Field
    class BaseField
      include ::Protobuf::Logging
      ::Protobuf::Optionable.inject(self, false) { ::Google::Protobuf::FieldOptions }

      ##
      # Constants
      #
      OBJECT_MODULE = ::Protobuf::Field::BaseFieldObjectDefinitions
      PACKED_TYPES = [
        ::Protobuf::WireType::VARINT,
        ::Protobuf::WireType::FIXED32,
        ::Protobuf::WireType::FIXED64,
      ].freeze

      ##
      # Attributes
      #
      attr_reader :default_value, :message_class, :name, :fully_qualified_name, :options, :rule, :tag, :type_class

      ##
      # Class Methods
      #

      def self.default
        nil
      end

      ##
      # Constructor
      #

      def initialize(message_class, rule, type_class, fully_qualified_name, tag, simple_name, options)
        @message_class = message_class
        @name = simple_name || fully_qualified_name
        @fully_qualified_name = fully_qualified_name
        @rule          = rule
        @tag           = tag
        @type_class    = type_class
        # Populate the option hash with all the original default field options, for backwards compatibility.
        # However, both default and custom options should ideally be accessed through the Optionable .{get,get!}_option functions.
        @options = options.slice(:ctype, :packed, :deprecated, :lazy, :jstype, :weak, :uninterpreted_option, :default, :extension)
        options.each do |option_name, value|
          set_option(option_name, value)
        end

        @extension = options.key?(:extension)
        @deprecated = options.key?(:deprecated)
        @required = rule == :required
        @repeated = rule == :repeated
        @optional = rule == :optional
        @packed = @repeated && options.key?(:packed)

        validate_packed_field if packed?
        define_accessor(simple_name, fully_qualified_name) if simple_name
        set_repeated_message!
        set_map!
        @value_from_values = nil
        @value_from_values_for_serialization = nil
        @field_predicate = nil
        @field_and_present_predicate = nil
        @set_field = nil
        @set_method = nil
        @to_message_hash = nil
        @to_message_hash_string_keys = nil
        @encode_to_stream = nil

        define_value_from_values!
        define_value_from_values_for_serialization!
        define_field_predicate!
        define_field_and_present_predicate!
        define_set_field!
        define_set_method!
        define_to_message_hash!
        define_encode_to_stream!
        set_default_value!
      end

      ##
      # Public Instance Methods
      #

      def acceptable?(_value)
        true
      end

      def coerce!(value)
        value
      end

      def decode(_bytes)
        fail NotImplementedError, "#{self.class.name}##{__method__}"
      end

      def default
        options[:default]
      end

      def set_default_value!
        @default_value ||= if optional? || required?
                             typed_default_value
                           elsif map?
                             ::Protobuf::Field::FieldHash.new(self).freeze
                           elsif repeated?
                             ::Protobuf::Field::FieldArray.new(self).freeze
                           else
                             fail "Unknown field label -- something went very wrong"
                           end
      end

      def define_encode_to_stream!
        @encode_to_stream = if repeated? && packed?
                              OBJECT_MODULE::RepeatedPackedEncodeToStream.new(self)
                            elsif repeated?
                              OBJECT_MODULE::RepeatedNotPackedEncodeToStream.new(self)
                            elsif message? || type_class == ::Protobuf::Field::BytesField
                              OBJECT_MODULE::BytesEncodeToStream.new(self)
                            elsif type_class == ::Protobuf::Field::StringField
                              OBJECT_MODULE::StringEncodeToStream.new(self)
                            else
                              OBJECT_MODULE::BaseEncodeToStream.new(self)
                            end
      end

      def encode_to_stream(value, stream)
        @encode_to_stream.call(value, stream)
      end

      def define_field_predicate!
        @field_predicate = if repeated?
                             OBJECT_MODULE::RepeatedFieldPredicate.new(self)
                           else
                             OBJECT_MODULE::BaseFieldPredicate.new(self)
                           end
      end

      def field?(values)
        @field_predicate.call(values)
      end

      def define_field_and_present_predicate!
        @field_and_present_predicate = if !repeated? && type_class == ::Protobuf::Field::BoolField # boolean present check
                                         OBJECT_MODULE::BoolFieldAndPresentPredicate.new(self)
                                       else
                                         OBJECT_MODULE::BaseFieldAndPresentPredicate.new(self)
                                       end
      end

      def field_and_present?(values)
        @field_and_present_predicate.call(values)
      end

      def define_value_from_values!
        @value_from_values = if map?
                               OBJECT_MODULE::MapValueFromValues.new(self)
                             elsif repeated?
                               OBJECT_MODULE::RepeatedFieldValueFromValues.new(self)
                             elsif type_class == ::Protobuf::Field::BoolField # boolean present check
                               OBJECT_MODULE::BoolFieldValueFromValues.new(self)
                             else
                               OBJECT_MODULE::BaseFieldValueFromValues.new(self)
                             end
      end

      def value_from_values(values)
        @value_from_values.call(values)
      end

      def define_value_from_values_for_serialization!
        @value_from_values_for_serialization = if map?
                                                 OBJECT_MODULE::MapValueFromValuesForSerialization.new(self)
                                               elsif repeated?
                                                 OBJECT_MODULE::RepeatedFieldValueFromValuesForSerialization.new(self)
                                               elsif type_class == ::Protobuf::Field::BoolField # boolean present check
                                                 OBJECT_MODULE::BoolFieldValueFromValuesForSerialization.new(self)
                                               else
                                                 OBJECT_MODULE::BaseFieldValueFromValuesForSerialization.new(self)
                                               end
      end

      def value_from_values_for_serialization(values)
        @value_from_values_for_serialization.call(values)
      end

      def define_set_field!
        @set_field = if map? && required?
                       OBJECT_MODULE::RequiredMapSetField.new(self)
                     elsif repeated? && required?
                       OBJECT_MODULE::RequiredRepeatedSetField.new(self)
                     elsif type_class == ::Protobuf::Field::StringField && required?
                       OBJECT_MODULE::RequiredStringSetField.new(self)
                     elsif required?
                       OBJECT_MODULE::RequiredBaseSetField.new(self)
                     elsif map?
                       OBJECT_MODULE::MapSetField.new(self)
                     elsif repeated?
                       OBJECT_MODULE::RepeatedSetField.new(self)
                     elsif type_class == ::Protobuf::Field::StringField
                       OBJECT_MODULE::StringSetField.new(self)
                     else
                       OBJECT_MODULE::BaseSetField.new(self)
                     end
      end

      def set_field(values, value, ignore_nil_for_repeated, message_instance)
        @set_field.call(values, value, ignore_nil_for_repeated, message_instance)
      end

      def define_to_message_hash!
        if message? || enum? || repeated? || map?
          @to_message_hash = OBJECT_MODULE::ToHashValueToMessageHash.new(self)
          @to_message_hash_string_keys = OBJECT_MODULE::ToHashValueToMessageHashWithStringKey.new(self)
        else
          @to_message_hash = OBJECT_MODULE::BaseToMessageHash.new(self)
          @to_message_hash_string_keys = OBJECT_MODULE::BaseToMessageHashWithStringKey.new(self)
        end
      end

      def to_message_hash(values, result)
        @to_message_hash.call(values, result)
      end

      def to_message_hash_with_string_key(values, result)
        @to_message_hash_string_keys.call(values, result)
      end

      def deprecated?
        @deprecated
      end

      def encode(_value)
        fail NotImplementedError, "#{self.class.name}##{__method__}"
      end

      def extension?
        @extension
      end

      def enum?
        false
      end

      def message?
        false
      end

      def set_map!
        set_repeated_message!
        @is_map = repeated_message? && type_class.get_option!(:map_entry)
      end

      def map?
        @is_map
      end

      def optional?
        @optional
      end

      def packed?
        @packed
      end

      def repeated?
        @repeated
      end

      def set_repeated_message!
        @repeated_message = repeated? && message?
      end

      def repeated_message?
        @repeated_message
      end

      def required?
        @required
      end

      def define_set_method!
        @set_method = if map?
                        OBJECT_MODULE::MapSetMethod.new(self)
                      elsif repeated? && packed?
                        OBJECT_MODULE::RepeatedPackedSetMethod.new(self)
                      elsif repeated?
                        OBJECT_MODULE::RepeatedNotPackedSetMethod.new(self)
                      else
                        OBJECT_MODULE::BaseSetMethod.new(self)
                      end
      end

      def set(message_instance, bytes)
        @set_method.call(message_instance, bytes)
      end

      def tag_encoded
        @tag_encoded ||= begin
                           case
                           when repeated? && packed?
                             ::Protobuf::Field::VarintField.encode((tag << 3) | ::Protobuf::WireType::LENGTH_DELIMITED)
                           else
                             ::Protobuf::Field::VarintField.encode((tag << 3) | wire_type)
                           end
                         end
      end

      # FIXME: add packed, deprecated, extension options to to_s output
      def to_s
        "#{rule} #{type_class} #{name} = #{tag} #{default ? "[default=#{default.inspect}]" : ''}"
      end

      ::Protobuf.deprecator.define_deprecated_methods(self, :type => :type_class)

      def wire_type
        ::Protobuf::WireType::VARINT
      end

      def fully_qualified_name_only!
        @name = @fully_qualified_name

        ##
        # Recreate all of the meta methods as they may have used the original `name` value
        #
        define_value_from_values!
        define_value_from_values_for_serialization!
        define_field_predicate!
        define_field_and_present_predicate!
        define_set_field!
        define_set_method!
        define_to_message_hash!
        define_encode_to_stream!
      end

      private

      ##
      # Private Instance Methods
      #

      def define_accessor(simple_field_name, fully_qualified_field_name)
        message_class.class_eval do
          define_method("#{simple_field_name}!") do
            @values[fully_qualified_field_name] if field?(fully_qualified_field_name)
          end
        end

        message_class.class_eval do
          define_method(simple_field_name) { self[fully_qualified_field_name] }
          define_method("#{simple_field_name}=") { |v| set_field(fully_qualified_field_name, v, false) }
        end

        return unless deprecated?

        ::Protobuf.field_deprecator.deprecate_method(message_class, simple_field_name)
        ::Protobuf.field_deprecator.deprecate_method(message_class, "#{simple_field_name}!")
        ::Protobuf.field_deprecator.deprecate_method(message_class, "#{simple_field_name}=")
      end

      def typed_default_value
        if default.nil?
          self.class.default
        else
          default
        end
      end

      def validate_packed_field
        if packed? && ! ::Protobuf::Field::BaseField::PACKED_TYPES.include?(wire_type)
          fail "Can't use packed encoding for '#{type_class}' type"
        end
      end
    end
  end
end
