require 'cucumber/cucumber_expressions/errors'
require 'cucumber/cucumber_expressions/cucumber_expression'
require 'cucumber/cucumber_expressions/regular_expression'

module Cucumber
  module CucumberExpressions
    class ExpressionFactory
      def initialize(parameter_type_registry)
        @parameter_type_registry = parameter_type_registry
      end

      def create_expression(string_or_regexp)
        case string_or_regexp
        when String then CucumberExpression.new(string_or_regexp, @parameter_type_registry)
        when Regexp then RegularExpression.new(string_or_regexp, @parameter_type_registry)
        else
          raise CucumberExpressionError.new("Can't create an expression from #{string_or_regexp.inspect}")
        end
      end
    end
  end
end
