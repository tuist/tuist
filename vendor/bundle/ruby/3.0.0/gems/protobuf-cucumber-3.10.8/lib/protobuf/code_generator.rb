require 'active_support/core_ext/module/aliasing'
require 'protobuf/generators/file_generator'

module Protobuf
  class CodeGenerator

    CodeGeneratorFatalError = Class.new(RuntimeError)

    def self.fatal(message)
      fail CodeGeneratorFatalError, message
    end

    def self.print_tag_warning_suppress
      STDERR.puts "Suppress tag warning output with PB_NO_TAG_WARNINGS=1."
      def self.print_tag_warning_suppress; end # rubocop:disable Lint/DuplicateMethods, Lint/NestedMethodDefinition
    end

    def self.warn(message)
      STDERR.puts("[WARN] #{message}")
    end

    private

    attr_accessor :request

    public

    def initialize(request_bytes)
      @request_bytes = request_bytes
      self.request = ::Google::Protobuf::Compiler::CodeGeneratorRequest.decode(request_bytes)
    end

    def eval_unknown_extensions!
      request.proto_file.each do |file_descriptor|
        ::Protobuf::Generators::FileGenerator.new(file_descriptor).eval_unknown_extensions!
      end
      self.request = ::Google::Protobuf::Compiler::CodeGeneratorRequest.decode(@request_bytes)
    end

    def generate_file(file_descriptor)
      ::Protobuf::Generators::FileGenerator.new(file_descriptor).generate_output_file
    end

    def response_bytes
      generated_files = request.proto_file.map do |file_descriptor|
        generate_file(file_descriptor)
      end

      ::Google::Protobuf::Compiler::CodeGeneratorResponse.encode(:file => generated_files)
    end

    Protobuf::Field::BaseField.module_eval do
      def define_set_method!
      end

      def set_without_options(message_instance, bytes)
        return message_instance[name] = decode(bytes) unless repeated?

        if map?
          hash = message_instance[name]
          entry = decode(bytes)
          # decoded value could be nil for an
          # enum value that is not recognized
          hash[entry.key] = entry.value unless entry.value.nil?
          return hash[entry.key]
        end

        return message_instance[name] << decode(bytes) unless packed?

        array = message_instance[name]
        stream = StringIO.new(bytes)

        if wire_type == ::Protobuf::WireType::VARINT
          array << decode(Varint.decode(stream)) until stream.eof?
        elsif wire_type == ::Protobuf::WireType::FIXED64
          array << decode(stream.read(8)) until stream.eof?
        elsif wire_type == ::Protobuf::WireType::FIXED32
          array << decode(stream.read(4)) until stream.eof?
        end
      end

      # Sets a MessageField that is known to be an option.
      # We must allow fields to be set one at a time, as option syntax allows us to
      # set each field within the option using a separate "option" line.
      def set_with_options(message_instance, bytes)
        if message_instance[name].is_a?(::Protobuf::Message)
          gp = Google::Protobuf
          if message_instance.is_a?(gp::EnumOptions) || message_instance.is_a?(gp::EnumValueOptions) ||
             message_instance.is_a?(gp::FieldOptions) || message_instance.is_a?(gp::FileOptions) ||
             message_instance.is_a?(gp::MethodOptions) || message_instance.is_a?(gp::ServiceOptions) ||
             message_instance.is_a?(gp::MessageOptions)

            original_field = message_instance[name]
            decoded_field = decode(bytes)
            decoded_field.each_field do |subfield, subvalue|
              option_set(original_field, subfield, subvalue) { decoded_field.field?(subfield.tag) }
            end
            return
          end
        end

        set_without_options(message_instance, bytes)
      end
      alias_method :set, :set_with_options

      def option_set(message_field, subfield, subvalue)
        return unless yield
        if subfield.repeated?
          message_field[subfield.tag].concat(subvalue)
        elsif message_field[subfield.tag] && subvalue.is_a?(::Protobuf::Message)
          subvalue.each_field do |f, v|
            option_set(message_field[subfield.tag], f, v) { subvalue.field?(f.tag) }
          end
        else
          message_field[subfield.tag] = subvalue
        end
      end
    end
  end
end
