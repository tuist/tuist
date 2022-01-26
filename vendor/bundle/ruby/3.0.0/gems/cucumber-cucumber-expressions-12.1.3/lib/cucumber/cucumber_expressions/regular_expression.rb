require 'cucumber/cucumber_expressions/argument'
require 'cucumber/cucumber_expressions/parameter_type'
require 'cucumber/cucumber_expressions/tree_regexp'

module Cucumber
  module CucumberExpressions
    class RegularExpression

      def initialize(expression_regexp, parameter_type_registry)
        @expression_regexp = expression_regexp
        @parameter_type_registry = parameter_type_registry
        @tree_regexp = TreeRegexp.new(@expression_regexp)
      end

      def match(text)
        parameter_types = @tree_regexp.group_builder.children.map do |group_builder|
          parameter_type_regexp = group_builder.source
          @parameter_type_registry.lookup_by_regexp(
            parameter_type_regexp,
            @expression_regexp,
            text
          ) || ParameterType.new(
            nil,
            parameter_type_regexp,
            String,
            lambda {|*s| s[0]},
            false,
            false
          )
        end

        Argument.build(@tree_regexp, text, parameter_types)
      end

      def regexp
        @expression_regexp
      end

      def source
        @expression_regexp.source
      end

      def to_s
        regexp.inspect
      end
    end
  end
end
