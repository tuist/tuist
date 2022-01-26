# frozen_string_literal: true

require 'delegate'
require 'cucumber/multiline_argument/data_table'
require 'cucumber/multiline_argument/doc_string'

module Cucumber
  module MultilineArgument
    class << self
      def from_core(node)
        builder.wrap(node)
      end

      def from(argument, location = nil, content_type = nil)
        location ||= Core::Test::Location.of_caller
        case argument
        when String
          builder.doc_string(Core::Test::DocString.new(argument, content_type))
        when Array
          location = location.on_line(argument.first.line..argument.last.line)
          builder.data_table(argument.map(&:cells), location)
        when DataTable, DocString, None
          argument
        when nil
          None.new
        else
          raise ArgumentError, "Don't know how to convert #{argument.class} #{argument.inspect} into a MultilineArgument"
        end
      end

      private

      def builder
        @builder ||= Builder.new
      end

      class Builder
        def wrap(node)
          @result = None.new
          node.describe_to(self)
          @result
        end

        def doc_string(node, *_args)
          @result = DocString.new(node)
        end

        def data_table(node, *_args)
          @result = DataTable.new(node)
        end
      end
    end

    class None
      def append_to(array); end

      def describe_to(visitor); end
    end
  end
end
