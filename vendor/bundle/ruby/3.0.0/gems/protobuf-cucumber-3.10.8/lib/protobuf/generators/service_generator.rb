require 'protobuf/generators/base'
require 'protobuf/generators/option_generator'

module Protobuf
  module Generators
    class ServiceGenerator < Base

      def compile
        run_once(:compile) do
          print_class(descriptor.name, :service) do
            print OptionGenerator.new(descriptor.options, current_indent).to_s if descriptor.options
            descriptor.method.each do |method_descriptor|
              print_method(method_descriptor)
            end
          end
        end
      end

      private

      def print_method(method_descriptor)
        request_klass = modulize(method_descriptor.input_type)
        response_klass = modulize(method_descriptor.output_type)
        name = ENV.key?('PB_USE_RAW_RPC_NAMES') ? method_descriptor.name : method_descriptor.name.underscore
        options = {}
        if method_descriptor.options
          method_descriptor.options.each_field do |field_option|
            option_value = method_descriptor.options[field_option.name]
            next unless method_descriptor.options.field?(field_option.name)
            options[field_option.fully_qualified_name] = serialize_value(option_value)
          end
        end

        rpc = "rpc :#{name}, #{request_klass}, #{response_klass}"

        if options.empty?
          puts rpc
          return
        end

        puts rpc + " do"
        options.each do |option_name, value|
          indent { puts "set_option #{option_name.inspect}, #{value}" }
        end
        puts "end"
      end

    end
  end
end
