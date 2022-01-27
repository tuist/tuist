require 'cucumber/cucumber_expressions/parameter_type_matcher'
require 'cucumber/cucumber_expressions/generated_expression'
require 'cucumber/cucumber_expressions/combinatorial_generated_expression_factory'

module Cucumber
  module CucumberExpressions
    class CucumberExpressionGenerator
      def initialize(parameter_type_registry)
        @parameter_type_registry = parameter_type_registry
      end

      def generate_expression(text)
        generate_expressions(text)[0]
      end

      def generate_expressions(text)
        parameter_type_combinations = []
        parameter_type_matchers = create_parameter_type_matchers(text)
        expression_template = ""
        pos = 0

        loop do
          matching_parameter_type_matchers = []
          parameter_type_matchers.each do |parameter_type_matcher|
            advanced_parameter_type_matcher = parameter_type_matcher.advance_to(pos)
            if advanced_parameter_type_matcher.find
              matching_parameter_type_matchers.push(advanced_parameter_type_matcher)
            end
          end

          if matching_parameter_type_matchers.any?
            matching_parameter_type_matchers = matching_parameter_type_matchers.sort
            best_parameter_type_matcher = matching_parameter_type_matchers[0]
            best_parameter_type_matchers = matching_parameter_type_matchers.select do |m|
              (m <=> best_parameter_type_matcher).zero?
            end

            # Build a list of parameter types without duplicates. The reason there
            # might be duplicates is that some parameter types have more than one regexp,
            # which means multiple ParameterTypeMatcher objects will have a reference to the
            # same ParameterType.
            # We're sorting the list so prefer_for_regexp_match parameter types are listed first.
            # Users are most likely to want these, so they should be listed at the top.
            parameter_types = []
            best_parameter_type_matchers.each do |parameter_type_matcher|
              unless parameter_types.include?(parameter_type_matcher.parameter_type)
                parameter_types.push(parameter_type_matcher.parameter_type)
              end
            end
            parameter_types.sort!

            parameter_type_combinations.push(parameter_types)

            expression_template += escape(text.slice(pos...best_parameter_type_matcher.start))
            expression_template += "{%s}"

            pos = best_parameter_type_matcher.start + best_parameter_type_matcher.group.length
          else
            break
          end

          break if pos >= text.length
        end

        expression_template += escape(text.slice(pos..-1))

        CombinatorialGeneratedExpressionFactory.new(
          expression_template,
          parameter_type_combinations
        ).generate_expressions
      end

    private

      def create_parameter_type_matchers(text)
        parameter_matchers = []
        @parameter_type_registry.parameter_types.each do |parameter_type|
          if parameter_type.use_for_snippets?
            parameter_matchers += create_parameter_type_matchers2(parameter_type, text)
          end
        end
        parameter_matchers
      end

      def create_parameter_type_matchers2(parameter_type, text)
        regexps = parameter_type.regexps
        regexps.map do |regexp|
          regexp = Regexp.new("(#{regexp})")
          ParameterTypeMatcher.new(parameter_type, regexp, text, 0)
        end
      end

      def escape(s)
        s.gsub(/%/, '%%')
        .gsub(/\(/, '\\(')
        .gsub(/{/, '\\{')
        .gsub(/\//, '\\/')
      end
    end
  end
end
