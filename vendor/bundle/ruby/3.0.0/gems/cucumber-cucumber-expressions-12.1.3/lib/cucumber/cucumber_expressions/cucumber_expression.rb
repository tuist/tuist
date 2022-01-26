require 'cucumber/cucumber_expressions/argument'
require 'cucumber/cucumber_expressions/tree_regexp'
require 'cucumber/cucumber_expressions/errors'
require 'cucumber/cucumber_expressions/cucumber_expression_parser'

module Cucumber
  module CucumberExpressions
    class CucumberExpression

      ESCAPE_PATTERN = /([\\^\[({$.|?*+})\]])/

      def initialize(expression, parameter_type_registry)
        @expression = expression
        @parameter_type_registry = parameter_type_registry
        @parameter_types = []
        parser = CucumberExpressionParser.new
        ast = parser.parse(expression)
        pattern = rewrite_to_regex(ast)
        @tree_regexp = TreeRegexp.new(pattern)
      end

      def match(text)
        Argument.build(@tree_regexp, text, @parameter_types)
      end

      def source
        @expression
      end

      def regexp
        @tree_regexp.regexp
      end

      def to_s
        @source.inspect
      end

      private

      def rewrite_to_regex(node)
        case node.type
        when NodeType::TEXT
          return escape_regex(node.text)
        when NodeType::OPTIONAL
          return rewrite_optional(node)
        when NodeType::ALTERNATION
          return rewrite_alternation(node)
        when NodeType::ALTERNATIVE
          return rewrite_alternative(node)
        when NodeType::PARAMETER
          return rewrite_parameter(node)
        when NodeType::EXPRESSION
          return rewrite_expression(node)
        else
          # Can't happen as long as the switch case is exhaustive
          raise "#{node.type}"
        end
      end

      def escape_regex(expression)
        expression.gsub(ESCAPE_PATTERN, '\\\\\1')
      end

      def rewrite_optional(node)
        assert_no_parameters(node) { |astNode| raise ParameterIsNotAllowedInOptional.new(astNode, @expression) }
        assert_no_optionals(node) { |astNode| raise OptionalIsNotAllowedInOptional.new(astNode, @expression) }
        assert_not_empty(node) { |astNode| raise OptionalMayNotBeEmpty.new(astNode, @expression) }
        regex = node.nodes.map { |n| rewrite_to_regex(n) }.join('')
        "(?:#{regex})?"
      end

      def rewrite_alternation(node)
        # Make sure the alternative parts aren't empty and don't contain parameter types
        node.nodes.each { |alternative|
          if alternative.nodes.length == 0
            raise AlternativeMayNotBeEmpty.new(alternative, @expression)
          end
          assert_not_empty(alternative) { |astNode| raise AlternativeMayNotExclusivelyContainOptionals.new(astNode, @expression) }
        }
        regex = node.nodes.map { |n| rewrite_to_regex(n) }.join('|')
        "(?:#{regex})"
      end

      def rewrite_alternative(node)
        node.nodes.map { |lastNode| rewrite_to_regex(lastNode) }.join('')
      end

      def rewrite_parameter(node)
        name = node.text
        parameter_type = @parameter_type_registry.lookup_by_type_name(name)
        if parameter_type.nil?
          raise UndefinedParameterTypeError.new(node, @expression, name)
        end
        @parameter_types.push(parameter_type)
        regexps = parameter_type.regexps
        if regexps.length == 1
          return "(#{regexps[0]})"
        end
        "((?:#{regexps.join(')|(?:')}))"
      end

      def rewrite_expression(node)
        regex = node.nodes.map { |n| rewrite_to_regex(n) }.join('')
        "^#{regex}$"
      end

      def assert_not_empty(node, &raise_error)
        text_nodes = node.nodes.select { |astNode| NodeType::TEXT == astNode.type }
        raise_error.call(node) if text_nodes.length == 0
      end

      def assert_no_parameters(node, &raise_error)
        nodes = node.nodes.select { |astNode| NodeType::PARAMETER == astNode.type }
        raise_error.call(nodes[0]) if nodes.length > 0
      end

      def assert_no_optionals(node, &raise_error)
        nodes = node.nodes.select { |astNode| NodeType::OPTIONAL == astNode.type }
        raise_error.call(nodes[0]) if nodes.length > 0
      end
    end
  end
end
