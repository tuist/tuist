require 'protobuf/generators/printable'

module Protobuf
  module Generators
    class Base
      include ::Protobuf::Generators::Printable

      def self.validate_tags(type_name, tags)
        return if tags.empty?

        unique_tags = tags.uniq

        if unique_tags.size < tags.size
          ::Protobuf::CodeGenerator.fatal("#{type_name} object has duplicate tags. Expected #{unique_tags.size} tags, but got #{tags.size}. Suppress with PB_NO_TAG_WARNINGS=1.")
        end

        unless ENV.key?('PB_NO_TAG_WARNINGS')
          expected_size = tags.max - tags.min + 1
          if tags.size < expected_size
            ::Protobuf::CodeGenerator.print_tag_warning_suppress
            ::Protobuf::CodeGenerator.warn("#{type_name} object should have #{expected_size} tags (#{tags.min}..#{tags.max}), but found #{tags.size} tags.")
          end
        end
      end

      attr_reader :descriptor, :namespace, :options

      def initialize(descriptor, indent_level = 0, options = {})
        @descriptor = descriptor
        @options = options
        @namespace = @options.fetch(:namespace) { [] }
        init_printer(indent_level)
      end

      def fully_qualified_type_namespace
        ".#{type_namespace.join('.')}"
      end

      def run_once(label)
        tracker_ivar = "@_#{label}_compiled"
        value_ivar = "@_#{label}_compiled_value"

        if instance_variable_get(tracker_ivar)
          return instance_variable_get(value_ivar)
        end

        return_value = yield
        instance_variable_set(tracker_ivar, true)
        instance_variable_set(value_ivar, return_value)
        return_value
      end

      def to_s
        compile
        print_contents # see Printable
      end

      def type_namespace
        @type_namespace ||= @namespace + [descriptor.name]
      end

      def serialize_value(value)
        case value
        when Message
          fields = value.each_field.map do |field, inner_value|
            next unless value.field?(field.name)
            serialized_inner_value = serialize_value(inner_value)
            "#{field.fully_qualified_name.inspect} => #{serialized_inner_value}"
          end.compact
          "{ #{fields.join(', ')} }"
        when Enum
          "::#{value.parent_class}::#{value.name}"
        when String
          value.inspect
        when nil
          "nil"
        when Array
          '[' + value.map { |x| serialize_value(x) }.join(', ') + ']'
        else
          value
        end
      end
    end
  end
end
