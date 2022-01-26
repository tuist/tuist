require 'protobuf/generators/enum_generator'
require 'protobuf/generators/extension_generator'
require 'protobuf/generators/field_generator'
require 'protobuf/generators/message_generator'
require 'protobuf/generators/option_generator'
require 'protobuf/generators/service_generator'

module Protobuf
  module Generators
    class GroupGenerator
      include ::Protobuf::Generators::Printable

      attr_reader :groups, :indent_level
      attr_writer :order

      def initialize(indent_level = 0)
        @groups = Hash.new { |h, k| h[k] = [] }
        @headers = {}
        @comments = {}
        @handlers = {}
        @indent_level = indent_level
        @order = [:enum, :message_declaration, :options, :message, :extended_message, :service]
        init_printer(indent_level)
      end

      def add_options(option_descriptor)
        @groups[:options] << OptionGenerator.new(option_descriptor, indent_level)
      end

      def add_enums(enum_descriptors, options)
        enum_descriptors.each do |enum_descriptor|
          @groups[:enum] << EnumGenerator.new(enum_descriptor, indent_level, options)
        end
      end

      def add_comment(type, message)
        @comments[type] = message
      end

      def add_extended_messages(extended_messages, skip_empty_fields = true)
        extended_messages.each do |message_type, field_descriptors|
          next if skip_empty_fields && field_descriptors.empty?
          @groups[:extended_message] << ExtensionGenerator.new(message_type, field_descriptors, indent_level)
        end
      end

      def add_extension_fields(field_descriptors)
        field_descriptors.each do |field_descriptor|
          @groups[:extension_field] << FieldGenerator.new(field_descriptor, nil, indent_level)
        end
      end

      def add_extension_ranges(extension_ranges, &item_handler)
        @groups[:extension_range] = extension_ranges
        @handlers[:extension_range] = item_handler
      end

      def add_header(type, message)
        @headers[type] = message
      end

      def add_message_declarations(descriptors)
        descriptors.each do |descriptor|
          # elide synthetic map entry messages (we handle map fields differently)
          next if descriptor.options.try(:map_entry?) { false }
          @groups[:message_declaration] << MessageGenerator.new(descriptor, indent_level, :declaration => true)
        end
      end

      def add_message_fields(field_descriptors, msg_descriptor)
        field_descriptors.each do |field_descriptor|
          @groups[:field] << FieldGenerator.new(field_descriptor, msg_descriptor, indent_level)
        end
      end

      def add_messages(descriptors, options = {})
        descriptors.each do |descriptor|
          # elide synthetic map entry message (we handle map fields differently)
          next if descriptor.options.try(:map_entry?) { false }
          @groups[:message] << MessageGenerator.new(descriptor, indent_level, options)
        end
      end

      def add_services(service_descriptors)
        service_descriptors.each do |service_descriptor|
          @groups[:service] << ServiceGenerator.new(service_descriptor, indent_level)
        end
      end

      def compile
        @order.each do |type|
          items = @groups[type]
          next if items.empty?

          item_handler = @handlers[type]

          item_header = @headers[type]
          header(item_header) if item_header

          item_comment = @comments[type]
          comment(item_comment) if item_comment

          items.each do |item|
            if item_handler
              puts item_handler.call(item)
            else
              print item.to_s
            end
          end

          puts if type == :message_declaration || type == :options
        end
      end

      def to_s
        compile
        print_contents
      end

    end
  end
end
