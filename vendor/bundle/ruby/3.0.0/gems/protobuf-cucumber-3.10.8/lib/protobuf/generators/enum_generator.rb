require 'protobuf/generators/base'
require 'protobuf/generators/option_generator'

module Protobuf
  module Generators
    class EnumGenerator < Base

      def compile
        run_once(:compile) do
          tags = []

          print_class(descriptor.name, :enum) do
            if descriptor.options
              print OptionGenerator.new(descriptor.options, current_indent).to_s
              puts
            end

            descriptor.value.each do |enum_value_descriptor|
              tags << enum_value_descriptor.number
              puts build_value(enum_value_descriptor)
            end
          end

          unless descriptor.options.try(:allow_alias)
            self.class.validate_tags(fully_qualified_type_namespace, tags)
          end
        end
      end

      def build_value(enum_value_descriptor)
        name = enum_value_descriptor.name
        name.upcase! if ENV.key?('PB_UPCASE_ENUMS')
        number = enum_value_descriptor.number
        "define :#{name}, #{number}"
      end

    end
  end
end
