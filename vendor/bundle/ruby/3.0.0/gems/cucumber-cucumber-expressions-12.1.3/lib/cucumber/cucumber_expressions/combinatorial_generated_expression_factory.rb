require('cucumber/cucumber_expressions/generated_expression')

module Cucumber
  module CucumberExpressions

    class CombinatorialGeneratedExpressionFactory
      def initialize(expression_template, parameter_type_combinations)
        @expression_template = expression_template
        @parameter_type_combinations = parameter_type_combinations
      end

      def generate_expressions
        generated_expressions = []
        generate_permutations(generated_expressions, 0, [])
        generated_expressions
      end

      # 256 generated expressions ought to be enough for anybody
      MAX_EXPRESSIONS = 256

      def generate_permutations(generated_expressions, depth, current_parameter_types)
        if generated_expressions.length >= MAX_EXPRESSIONS
          return
        end

        if depth == @parameter_type_combinations.length
          generated_expression = GeneratedExpression.new(@expression_template, current_parameter_types)
          generated_expressions.push(generated_expression)
          return
        end

        (0...@parameter_type_combinations[depth].length).each do |i|
          # Avoid recursion if no elements can be added.
          if generated_expressions.length >= MAX_EXPRESSIONS
            return
          end
          new_current_parameter_types = current_parameter_types.dup # clone
          new_current_parameter_types.push(@parameter_type_combinations[depth][i])
          generate_permutations(
              generated_expressions,
              depth + 1,
              new_current_parameter_types
          )
        end
      end
    end

  end
end
