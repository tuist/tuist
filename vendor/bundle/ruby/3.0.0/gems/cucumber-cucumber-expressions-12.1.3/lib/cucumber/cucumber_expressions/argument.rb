require 'cucumber/cucumber_expressions/group'
require 'cucumber/cucumber_expressions/errors'

module Cucumber
  module CucumberExpressions
    class Argument
      attr_reader :group, :parameter_type

      def self.build(tree_regexp, text, parameter_types)
        group = tree_regexp.match(text)
        return nil if group.nil?

        arg_groups = group.children

        if arg_groups.length != parameter_types.length
          raise CucumberExpressionError.new(
              "Expression #{tree_regexp.regexp.inspect} has #{arg_groups.length} capture groups (#{arg_groups.map(&:value)}), but there were #{parameter_types.length} parameter types (#{parameter_types.map(&:name)})"
          )
        end

        parameter_types.zip(arg_groups).map do |parameter_type, arg_group|
          Argument.new(arg_group, parameter_type)
        end
      end

      def initialize(group, parameter_type)
        @group, @parameter_type = group, parameter_type
      end

      def value(self_obj=:nil)
        raise "No self_obj" if self_obj == :nil
        group_values = @group ? @group.values : nil
        @parameter_type.transform(self_obj, group_values)
      end
    end
  end
end
