require 'protobuf/generators/base'
require 'protobuf/generators/group_generator'

module Protobuf
  module Generators
    class ExtensionGenerator < Base

      def initialize(message_type, field_descriptors, indent_level)
        super(nil, indent_level)
        @message_type = modulize(message_type)
        @field_descriptors = field_descriptors
      end

      def compile
        run_once(:compile) do
          print_class(@message_type, :message) do
            group = GroupGenerator.new(current_indent)
            group.add_extension_fields(@field_descriptors)
            group.order = [:extension_field]
            print group.to_s
          end
        end
      end

    end
  end
end
