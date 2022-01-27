require 'cucumber/cucumber_expressions/parameter_type'
require 'cucumber/cucumber_expressions/errors'
require 'cucumber/cucumber_expressions/cucumber_expression_generator'

module Cucumber
  module CucumberExpressions
    class ParameterTypeRegistry
      INTEGER_REGEXPS = [/-?\d+/, /\d+/]
      FLOAT_REGEXP = /(?=.*\d.*)[-+]?\d*(?:\.(?=\d.*))?\d*(?:\d+[E][-+]?\d+)?/
      WORD_REGEXP = /[^\s]+/
      STRING_REGEXP = /"([^"\\]*(\\.[^"\\]*)*)"|'([^'\\]*(\\.[^'\\]*)*)'/
      ANONYMOUS_REGEXP = /.*/

      def initialize
        @parameter_type_by_name = {}
        @parameter_types_by_regexp = Hash.new {|hash, regexp| hash[regexp] = []}

        define_parameter_type(ParameterType.new('int', INTEGER_REGEXPS, Integer, lambda {|s = nil| s && s.to_i}, true, true))
        define_parameter_type(ParameterType.new('float', FLOAT_REGEXP, Float, lambda {|s = nil| s && s.to_f}, true, false))
        define_parameter_type(ParameterType.new('word', WORD_REGEXP, String, lambda {|s = nil| s}, false, false))
        define_parameter_type(ParameterType.new('string', STRING_REGEXP, String, lambda { |s1, s2| arg = s1 != nil ? s1 : s2; arg.gsub(/\\"/, '"').gsub(/\\'/, "'")}, true, false))
        define_parameter_type(ParameterType.new('', ANONYMOUS_REGEXP, String, lambda {|s = nil| s}, false, true))
      end

      def lookup_by_type_name(name)
        @parameter_type_by_name[name]
      end

      def lookup_by_regexp(parameter_type_regexp, expression_regexp, text)
        parameter_types = @parameter_types_by_regexp[parameter_type_regexp]
        return nil if parameter_types.nil?
        if parameter_types.length > 1 && !parameter_types[0].prefer_for_regexp_match?
          # We don't do this check on insertion because we only want to restrict
          # ambiguity when we look up by Regexp. Users of CucumberExpression should
          # not be restricted.
          generated_expressions = CucumberExpressionGenerator.new(self).generate_expressions(text)
          raise AmbiguousParameterTypeError.new(parameter_type_regexp, expression_regexp, parameter_types, generated_expressions)
        end
        parameter_types.first
      end

      def parameter_types
        @parameter_type_by_name.values
      end

      def define_parameter_type(parameter_type)
        if parameter_type.name != nil
          if @parameter_type_by_name.has_key?(parameter_type.name)
            if parameter_type.name.length == 0
              raise CucumberExpressionError.new("The anonymous parameter type has already been defined")
            else
              raise CucumberExpressionError.new("There is already a parameter with name #{parameter_type.name}")
            end
          end
          @parameter_type_by_name[parameter_type.name] = parameter_type
        end

        parameter_type.regexps.each do |parameter_type_regexp|
          parameter_types = @parameter_types_by_regexp[parameter_type_regexp]
          if parameter_types.any? && parameter_types[0].prefer_for_regexp_match? && parameter_type.prefer_for_regexp_match?
            raise CucumberExpressionError.new("There can only be one preferential parameter type per regexp. The regexp /#{parameter_type_regexp}/ is used for two preferential parameter types, {#{parameter_types[0].name}} and {#{parameter_type.name}}")
          end
          parameter_types.push(parameter_type)
          parameter_types.sort!
        end
      end

    end
  end
end
