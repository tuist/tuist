module Cucumber
  module CucumberExpressions
    class GeneratedExpression
      attr_reader :parameter_types

      def initialize(expression_template, parameters_types)
        @expression_template, @parameter_types = expression_template, parameters_types
      end

      def source
        sprintf(@expression_template, *@parameter_types.map(&:name))
      end

      def parameter_names
        usage_by_type_name = Hash.new(0)
        @parameter_types.map do |t|
          get_parameter_name(t.name, usage_by_type_name)
        end
      end

      private

      def get_parameter_name(type_name, usage_by_type_name)
        count = usage_by_type_name[type_name]
        count += 1
        usage_by_type_name[type_name] = count
        count == 1 ? type_name : "#{type_name}#{count}"
      end
    end
  end
end
