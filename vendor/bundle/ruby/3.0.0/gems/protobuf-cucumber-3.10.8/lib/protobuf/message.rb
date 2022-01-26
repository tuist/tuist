require 'protobuf/message/fields'
require 'protobuf/message/serialization'
require 'protobuf/varint'

module Protobuf
  class Message

    ##
    # Includes & Extends
    #

    extend ::Protobuf::Message::Fields
    include ::Protobuf::Message::Serialization
    ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::MessageOptions }

    ##
    # Class Methods
    #

    def self.to_json
      name
    end

    def self.from_json(json)
      fields = normalize_json(JSON.parse(json))
      new(fields)
    end

    def self.normalize_json(ob)
      case ob
      when Array
        ob.map { |value| normalize_json(value) }
      when Hash
        Hash[*ob.flat_map { |key, value| [key.underscore, normalize_json(value)] }]
      else
        ob
      end
    end

    ##
    # Constructor
    #

    def initialize(fields = {})
      @values = {}
      fields.to_hash.each do |name, value|
        set_field(name, value, true)
      end

      yield self if block_given?
    end

    ##
    # Public Instance Methods
    #

    def clear!
      @values.delete_if do |_, value|
        if value.is_a?(::Protobuf::Field::FieldArray) || value.is_a?(::Protobuf::Field::FieldHash)
          value.clear
          false
        else
          true
        end
      end
      self
    end

    def clone
      copy_to(super, :clone)
    end

    def dup
      copy_to(super, :dup)
    end

    # Iterate over every field, invoking the given block
    #
    def each_field
      return to_enum(:each_field) unless block_given?

      self.class.all_fields.each do |field|
        value = self[field.name]
        yield(field, value)
      end
    end

    def each_field_for_serialization
      _protobuf_message_unset_required_field_tags.each do |tag|
        fail ::Protobuf::SerializationError, "Required field #{self.class.name}##{_protobuf_message_field[tag].name} does not have a value."
      end

      @values.each_key do |fully_qualified_name|
        field = _protobuf_message_field[fully_qualified_name]
        yield(field, field.value_from_values_for_serialization(@values))
      end
    end

    def field?(name)
      field = _protobuf_message_field[name]

      if field
        field.field?(@values)
      else
        false
      end
    end
    alias :respond_to_has? field?
    ::Protobuf.deprecator.define_deprecated_methods(self, :has_field? => :field?)

    def inspect
      attrs = self.class.fields.map do |field|
        [field.name, self[field.name].inspect].join('=')
      end.join(' ')

      "#<#{self.class} #{attrs}>"
    end

    def respond_to_has_and_present?(key)
      field = _protobuf_message_field[key]

      if field
        field.field_and_present?(@values)
      else
        false
      end
    end

    # Return a hash-representation of the given fields for this message type.
    def to_hash
      result = {}

      @values.each_key do |field_name|
        field = _protobuf_message_field[field_name]
        field.to_message_hash(@values, result)
      end

      result
    end

    def to_hash_with_string_keys
      result = {}

      @values.each_key do |field_name|
        field = _protobuf_message_field[field_name]
        field.to_message_hash_with_string_key(@values, result)
      end

      result
    end

    def to_json(options = {})
      to_json_hash(options).to_json(options)
    end

    # Return a hash-representation of the given fields for this message type that
    # is safe to convert to JSON.
    def to_json_hash(options = {})
      result = {}

      proto3 = options[:proto3] || options[:lower_camel_case]

      @values.each_key do |field_name|
        value = self[field_name]
        field = self.class.get_field(field_name, true)

        # NB: to_json_hash_value should come before json_encode so as to handle
        # repeated fields without extra logic.
        hashed_value = if value.respond_to?(:to_json_hash_value) && !field.is_a?(::Protobuf::Field::EnumField)
                         value.to_json_hash_value(options)
                       elsif field.respond_to?(:json_encode)
                         field.json_encode(value, options)
                       else
                         value
                       end

        if proto3 && (hashed_value.nil? || value == field.class.default rescue field.default rescue nil)
          result.delete(field.name)
        else
          key = proto3 ? field.name.to_s.camelize(:lower).to_sym : field.name
          result[key] = hashed_value
        end
      end

      result
    end

    def to_proto
      self
    end

    def ==(other)
      return false unless other.is_a?(self.class)
      each_field do |field, value|
        return false unless value == other[field.name]
      end
      true
    end

    def [](name)
      field = _protobuf_message_field[name]
      field.value_from_values(@values)
    rescue # not having a field should be the exceptional state
      raise if field
      fail ArgumentError, "invalid field name=#{name.inspect}"
    end

    def []=(name, value)
      set_field(name, value, true)
    end

    def set_field(name, value, ignore_nil_for_repeated, field = nil)
      field ||= _protobuf_message_field[name]

      if field
        field.set_field(@values, value, ignore_nil_for_repeated, self)
      else
        fail(::Protobuf::FieldNotDefinedError, name) unless ::Protobuf.ignore_unknown_fields?
      end
    end

    ##
    # Instance Aliases
    #
    alias :to_hash_value to_hash
    alias :to_json_hash_value to_json_hash
    alias :to_proto_hash to_hash
    alias :responds_to_has? respond_to_has?
    alias :respond_to_and_has? respond_to_has?
    alias :responds_to_and_has? respond_to_has?
    alias :respond_to_has_present? respond_to_has_and_present?
    alias :respond_to_and_has_present? respond_to_has_and_present?
    alias :respond_to_and_has_and_present? respond_to_has_and_present?
    alias :responds_to_has_present? respond_to_has_and_present?
    alias :responds_to_and_has_present? respond_to_has_and_present?
    alias :responds_to_and_has_and_present? respond_to_has_and_present?

    ##
    # Private Instance Methods
    #

    private

    def copy_to(object, method)
      duplicate = proc do |obj|
        case obj
        when Message, String then obj.__send__(method)
        else                      obj
        end
      end

      object.__send__(:initialize)
      @values.each do |name, value|
        if value.is_a?(::Protobuf::Field::FieldArray)
          object[name].replace(value.map { |v| duplicate.call(v) })
        else
          object[name] = duplicate.call(value)
        end
      end
      object
    end

  end
end
