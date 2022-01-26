require 'protobuf/generators/base'
require 'protobuf/generators/group_generator'

module Protobuf
  module Generators
    class MessageGenerator < Base

      def initialize(descriptor, indent_level, options = {})
        super
        @only_declarations = options.fetch(:declaration) { false }
        @extension_fields = options.fetch(:extension_fields) { {} }
      end

      def compile
        run_once(:compile) do
          if @only_declarations
            compile_declaration
          else
            compile_message
          end
        end
      end

      def compile_declaration
        run_once(:compile_declaration) do
          if printable?
            print_class(descriptor.name, :message) do
              group = GroupGenerator.new(current_indent)
              group.add_enums(descriptor.enum_type, :namespace => type_namespace)
              group.add_message_declarations(descriptor.nested_type)
              print group.to_s
            end
          else
            print_class(descriptor.name, :message)
          end
        end
      end

      def compile_message
        run_once(:compile_message) do
          if printable?
            print_class(descriptor.name, nil) do
              group = GroupGenerator.new(current_indent)
              group.add_messages(descriptor.nested_type, :extension_fields => @extension_fields, :namespace => type_namespace)
              group.add_comment(:options, 'Message Options')
              group.add_options(descriptor.options) if options?
              group.add_message_fields(descriptor.field, descriptor)
              self.class.validate_tags(fully_qualified_type_namespace, descriptor.field.map(&:number))

              group.add_comment(:extension_range, 'Extension Fields')
              group.add_extension_ranges(descriptor.extension_range) do |extension_range|
                "extensions #{extension_range.start}...#{extension_range.end}"
              end

              group.add_extension_fields(message_extension_fields)

              group.order = [:message, :options, :field, :extension_range, :extension_field]
              print group.to_s
            end
          end
        end
      end

      private

      def extensions?
        !message_extension_fields.empty?
      end

      def fields?
        descriptor.field.count > 0
      end

      def options?
        descriptor.options
      end

      def nested_enums?
        descriptor.enum_type.count > 0
      end

      def nested_messages?
        descriptor.nested_type.count > 0
      end

      def nested_types?
        nested_enums? || nested_messages?
      end

      def printable?
        if @only_declarations
          nested_types?
        else
          fields? || nested_messages? || extensions? || options?
        end
      end

      def message_extension_fields
        @extension_fields.fetch(fully_qualified_type_namespace) { [] }
      end

    end
  end
end
