require 'set'
require 'protobuf/generators/base'
require 'protobuf/generators/group_generator'

module Protobuf
  module Generators
    class FileGenerator < Base

      attr_reader :output_file

      def initialize(*args)
        super
        @output_file = ::Google::Protobuf::Compiler::CodeGeneratorResponse::File.new(:name => file_name)
        @extension_fields = Hash.new { |h, k| h[k] = [] }
        @known_messages = {}
        @known_enums = {}
        @dangling_messages = {}
      end

      def file_name
        convert_filename(descriptor.name, false)
      end

      def compile
        run_once(:compile) do
          map_extensions(descriptor, [descriptor.package])

          print_file_comment
          print_generic_requires
          print_import_requires

          print_package do
            inject_optionable
            group = GroupGenerator.new(current_indent)
            group.add_options(descriptor.options) if descriptor.options
            group.add_enums(descriptor.enum_type, :namespace => [descriptor.package])
            group.add_message_declarations(descriptor.message_type)
            group.add_messages(descriptor.message_type, :extension_fields => @extension_fields, :namespace => [descriptor.package])
            group.add_extended_messages(unknown_extensions)
            group.add_services(descriptor.service)

            group.add_header(:enum, 'Enum Classes')
            group.add_header(:message_declaration, 'Message Classes')
            group.add_header(:options, 'File Options')
            group.add_header(:message, 'Message Fields')
            group.add_header(:extended_message, 'Extended Message Fields')
            group.add_header(:service, 'Service Classes')
            print group.to_s
          end

        end
      end

      def unknown_extensions
        @unknown_extensions ||= @extension_fields.map do |message_name, fields|
          message_klass = modulize(message_name).safe_constantize
          if message_klass
            unknown_fields = fields.reject do |field|
              @known_messages[message_name] && message_klass.get_field(field.name, true)
            end
            [message_name, unknown_fields]
          else
            [message_name, fields]
          end
        end
      end

      def generate_output_file
        compile
        output_file.content = to_s
        output_file
      end

      # Recursively map out all extensions known in this file.
      # The key is the type_name of the message being extended, and
      # the value is an array of field descriptors.
      #
      def map_extensions(descriptor, namespaces)
        if fully_qualified_token?(descriptor.name)
          fully_qualified_namespace = descriptor.name
        elsif !(namespace = namespaces.reject(&:empty?).join(".")).empty?
          fully_qualified_namespace = ".#{namespace}"
        end
        # Record all the message descriptor name's we encounter (should be the whole tree).
        if descriptor.is_a?(::Google::Protobuf::DescriptorProto)
          @known_messages[fully_qualified_namespace || descriptor.name] = descriptor
        elsif descriptor.is_a?(::Google::Protobuf::EnumDescriptorProto)
          @known_enums[fully_qualified_namespace || descriptor.name] = descriptor
          return
        end

        descriptor.extension.each do |field_descriptor|
          unless fully_qualified_token?(field_descriptor.name) && fully_qualified_namespace
            field_descriptor.name = "#{fully_qualified_namespace}.#{field_descriptor.name}"
          end
          @extension_fields[field_descriptor.extendee] << field_descriptor
        end

        [:message_type, :nested_type, :enum_type].each do |type|
          next unless descriptor.respond_to_has_and_present?(type)

          descriptor.public_send(type).each do |type_descriptor|
            map_extensions(type_descriptor, (namespaces + [type_descriptor.name]))
          end
        end
      end

      def print_file_comment
        puts "# encoding: utf-8"
        puts
        puts "##"
        puts "# This file is auto-generated. DO NOT EDIT!"
        puts "#"
      end

      def print_generic_requires
        print_require("protobuf")
        print_require("protobuf/rpc/service") if descriptor.service.count > 0
        puts
      end

      def print_import_requires
        return if descriptor.dependency.empty?

        header "Imports"

        descriptor.dependency.each do |dependency|
          print_require(convert_filename(dependency), ENV.key?('PB_REQUIRE_RELATIVE'))
        end

        puts
      end

      def print_package(&block)
        namespaces = descriptor.package.split('.')
        if namespaces.empty? && ENV.key?('PB_ALLOW_DEFAULT_PACKAGE_NAME')
          namespaces = [File.basename(descriptor.name).sub('.proto', '')]
        end
        namespaces.reverse.reduce(block) do |previous, namespace|
          -> { print_module(namespace, &previous) }
        end.call
      end

      def eval_unknown_extensions!
        @@evaled_dependencies ||= Set.new # rubocop:disable Style/ClassVars
        @@all_messages ||= {} # rubocop:disable Style/ClassVars
        @@all_enums ||= {} # rubocop:disable Style/ClassVars

        map_extensions(descriptor, [descriptor.package])
        @known_messages.each do |name, descriptor|
          @@all_messages[name] = descriptor
        end
        @known_enums.each do |name, descriptor|
          @@all_enums[name] = descriptor
        end

        # create package namespace
        print_package {}
        eval_code

        unknown_extensions.each do |extendee, fields|
          eval_dependencies(extendee)
          fields.each do |field|
            eval_dependencies(field.type_name)
          end
        end
        group = GroupGenerator.new(0)
        group.add_extended_messages(unknown_extensions, false)
        print group.to_s
        eval_code
      rescue => e
        warn "Error loading unknown extensions #{descriptor.name.inspect} error=#{e}"
        raise e
      end

      private

      def convert_filename(filename, for_require = true)
        filename.sub(/\.proto/, (for_require ? '.pb' : '.pb.rb'))
      end

      def fully_qualified_token?(token)
        token[0] == '.'
      end

      def eval_dependencies(name, namespace = nil)
        name = "#{namespace}.#{name}" if namespace && !fully_qualified_token?(name)
        return if name.empty? || @@evaled_dependencies.include?(name) || modulize(name).safe_constantize

        # if name = .foo.bar.Baz look for classes / modules named ::Foo::Bar and ::Foo
        # module == pure namespace (e.g. the descriptor package name)
        # class == nested messages
        create_ruby_namespace_heiarchy(name)

        if (message = @@all_messages[name])
          # Create the blank namespace in case there are nested types
          eval_message_code(name)

          message.nested_type.each do |nested_type|
            eval_dependencies(nested_type.name, name) unless nested_type.name.empty?
          end
          message.field.each do |field|
            eval_dependencies(field.type_name, name) unless field.type_name.empty?
          end
          message.enum_type.each do |enum_type|
            eval_dependencies(enum_type.name, name)
          end

          # Check @@evaled_dependencies again in case there was a dependency
          # loop that already loaded this message
          return if @@evaled_dependencies.include?(name)
          eval_message_code(name, message.field)
          @@evaled_dependencies << name

        elsif (enum = @@all_enums[name])
          # Check @@evaled_dependencies again in case there was a dependency
          # loop that already loaded this enum
          return if @@evaled_dependencies.include?(name)
          namespace = name.split(".")
          eval_enum_code(enum, namespace[0..-2].join("."))
          @@evaled_dependencies << name
        else
          fail "Error loading unknown dependencies, could not find message or enum #{name.inspect}"
        end
      end

      def eval_message_code(fully_qualified_namespace, fields = [])
        group = GroupGenerator.new(0)
        group.add_extended_messages({ fully_qualified_namespace => fields }, false)
        print group.to_s
        eval_code
      end

      def eval_enum_code(enum, fully_qualified_namespace)
        group = GroupGenerator.new(0)
        group.add_enums([enum], :namespace => [fully_qualified_namespace])
        print group.to_s
        eval_code(modulize(fully_qualified_namespace).safe_constantize || Object)
      end

      def eval_code(context = Object)
        warn "#{context.inspect}.module_eval #{print_contents.inspect}" if ENV['PB_DEBUG']
        context.module_eval print_contents.to_s
        @io.truncate(0)
        @io.rewind
      end

      def create_ruby_namespace_heiarchy(namespace)
        loop do
          namespace, _match, _tail = namespace.rpartition(".")
          break if namespace.empty?
          eval_dependencies(namespace)
        end
      end

      def inject_optionable
        return if descriptor.package.empty? && !ENV.key?('PB_ALLOW_DEFAULT_PACKAGE_NAME')
        puts "::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }"
      end
    end
  end
end
