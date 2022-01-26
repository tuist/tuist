require 'cucumber/cucumber_expressions/ast'

module Cucumber
  module CucumberExpressions
    class CucumberExpressionError < StandardError

      def build_message(
          index,
          expression,
          pointer,
          problem,
          solution
      )
        m = <<-EOF
This Cucumber Expression has a problem at column #{index + 1}:

#{expression}
#{pointer}
#{problem}.
#{solution}
        EOF
        m.strip
      end

      def point_at(index)
        ' ' * index + '^'
      end

      def point_at_located(node)
        pointer = [point_at(node.start)]
        if node.start + 1 < node.end
          for _ in node.start + 1...node.end - 1
            pointer.push('-')
          end
          pointer.push('^')
        end
        pointer.join('')
      end
    end

    class AlternativeMayNotExclusivelyContainOptionals < CucumberExpressionError
      def initialize(node, expression)
        super(build_message(
                  node.start,
                  expression,
                  point_at_located(node),
                  'An alternative may not exclusively contain optionals',
                  "If you did not mean to use an optional you can use '\\(' to escape the the '('"
              ))
      end
    end

    class AlternativeMayNotBeEmpty < CucumberExpressionError
      def initialize(node, expression)
        super(build_message(
                  node.start,
                  expression,
                  point_at_located(node),
                  'Alternative may not be empty',
                  "If you did not mean to use an alternative you can use '\\/' to escape the the '/'"
              ))
      end
    end

    class CantEscape < CucumberExpressionError
      def initialize(expression, index)
        super(build_message(
                  index,
                  expression,
                  point_at(index),
                  "Only the characters '{', '}', '(', ')', '\\', '/' and whitespace can be escaped",
                  "If you did mean to use an '\\' you can use '\\\\' to escape it"
              ))
      end
    end

    class OptionalMayNotBeEmpty < CucumberExpressionError
      def initialize(node, expression)
        super(build_message(
                  node.start,
                  expression,
                  point_at_located(node),
                  'An optional must contain some text',
                  "If you did not mean to use an optional you can use '\\(' to escape the the '('"
              ))
      end
    end

    class ParameterIsNotAllowedInOptional < CucumberExpressionError
      def initialize(node, expression)
        super(build_message(
                  node.start,
                  expression,
                  point_at_located(node),
                  'An optional may not contain a parameter type',
                  "If you did not mean to use an parameter type you can use '\\{' to escape the the '{'"
              ))
      end
    end

    class OptionalIsNotAllowedInOptional < CucumberExpressionError
      def initialize(node, expression)
        super(build_message(
                  node.start,
                  expression,
                  point_at_located(node),
                  'An optional may not contain an other optional',
                  "If you did not mean to use an optional type you can use '\\(' to escape the the '('. For more complicated expressions consider using a regular expression instead."
              ))
      end
    end

    class TheEndOfLineCannotBeEscaped < CucumberExpressionError
      def initialize(expression)
        index = expression.codepoints.length - 1
        super(build_message(
                  index,
                  expression,
                  point_at(index),
                  'The end of line can not be escaped',
                  "You can use '\\\\' to escape the the '\\'"
              ))
      end
    end

    class MissingEndToken < CucumberExpressionError
      def initialize(expression, begin_token, end_token, current)
        begin_symbol = Token::symbol_of(begin_token)
        end_symbol = Token::symbol_of(end_token)
        purpose = Token::purpose_of(begin_token)
        super(build_message(
                  current.start,
                  expression,
                  point_at_located(current),
                  "The '#{begin_symbol}' does not have a matching '#{end_symbol}'",
                  "If you did not intend to use #{purpose} you can use '\\#{begin_symbol}' to escape the #{purpose}"
              ))
      end
    end

    class AlternationNotAllowedInOptional < CucumberExpressionError
      def initialize(expression, current)
        super(build_message(
                  current.start,
                  expression,
                  point_at_located(current),
                  "An alternation can not be used inside an optional",
                  "You can use '\\/' to escape the the '/'"
              ))
      end
    end

    class InvalidParameterTypeName < CucumberExpressionError
      def initialize(type_name)
        super("Illegal character in parameter name {#{type_name}}. " +
                  "Parameter names may not contain '{', '}', '(', ')', '\\' or '/'")
      end
    end


    class InvalidParameterTypeNameInNode < CucumberExpressionError
      def initialize(expression, token)
        super(build_message(
                  token.start,
                  expression,
                  point_at_located(token),
                  "Parameter names may not contain '{', '}', '(', ')', '\\' or '/'",
                  "Did you mean to use a regular expression?"
              ))
      end
    end

    class UndefinedParameterTypeError < CucumberExpressionError
      attr_reader :undefined_parameter_type_name

      def initialize(node, expression, undefined_parameter_type_name)
        super(build_message(node.start,
                            expression,
                            point_at_located(node),
                            "Undefined parameter type '#{undefined_parameter_type_name}'",
                            "Please register a ParameterType for '#{undefined_parameter_type_name}'"))
        @undefined_parameter_type_name = undefined_parameter_type_name
      end
    end

    class AmbiguousParameterTypeError < CucumberExpressionError
      def initialize(parameter_type_regexp, expression_regexp, parameter_types, generated_expressions)
        super(<<-EOM)
Your Regular Expression /#{expression_regexp.source}/
matches multiple parameter types with regexp /#{parameter_type_regexp}/:
   #{parameter_type_names(parameter_types)}

I couldn't decide which one to use. You have two options:

1) Use a Cucumber Expression instead of a Regular Expression. Try one of these:
   #{expressions(generated_expressions)}

2) Make one of the parameter types preferential and continue to use a Regular Expression.

        EOM
      end

      private

      def parameter_type_names(parameter_types)
        parameter_types.map { |p| "{#{p.name}}" }.join("\n   ")
      end

      def expressions(generated_expressions)
        generated_expressions.map { |ge| ge.source }.join("\n   ")
      end
    end
  end
end
