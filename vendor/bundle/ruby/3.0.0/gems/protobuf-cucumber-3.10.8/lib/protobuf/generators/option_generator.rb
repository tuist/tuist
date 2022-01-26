require 'protobuf/generators/base'

module Protobuf
  module Generators
    class OptionGenerator < Base
      def compile
        run_once(:compile) do
          descriptor.each_field.map do |field, value|
            next unless descriptor.field?(field.name)
            serialized_value = serialize_value(value)
            puts "set_option #{field.fully_qualified_name.inspect}, #{serialized_value}"
          end
        end
      end
    end
  end
end
