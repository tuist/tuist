require 'cucumber/cucumber_expressions/ast'
require 'cucumber/cucumber_expressions/errors'
require 'cucumber/cucumber_expressions/cucumber_expression_tokenizer'

module Cucumber
  module CucumberExpressions
    class CucumberExpressionParser
      def parse(expression)
        # text := whitespace | ')' | '}' | .
        parse_text = lambda do |_, tokens, current|
          token = tokens[current]
          case token.type
          when TokenType::WHITE_SPACE, TokenType::TEXT, TokenType::END_PARAMETER, TokenType::END_OPTIONAL
            return 1, [Node.new(NodeType::TEXT, nil, token.text, token.start, token.end)]
          when TokenType::ALTERNATION
            raise AlternationNotAllowedInOptional.new(expression, token)
          when TokenType::BEGIN_PARAMETER, TokenType::START_OF_LINE, TokenType::END_OF_LINE, TokenType::BEGIN_OPTIONAL
          else
            # If configured correctly this will never happen
            return 0, nil
          end
          # If configured correctly this will never happen
          return 0, nil
        end

        # name := whitespace | .
        parse_name = lambda do |_, tokens, current|
          token = tokens[current]
          case token.type
          when TokenType::WHITE_SPACE, TokenType::TEXT
            return 1, [Node.new(NodeType::TEXT, nil, token.text, token.start, token.end)]
          when TokenType::BEGIN_PARAMETER, TokenType::END_PARAMETER, TokenType::BEGIN_OPTIONAL, TokenType::END_OPTIONAL, TokenType::ALTERNATION
            raise InvalidParameterTypeNameInNode.new(expression, token)
          when TokenType::START_OF_LINE, TokenType::END_OF_LINE
            # If configured correctly this will never happen
            return 0, nil
          else
            # If configured correctly this will never happen
            return 0, nil
          end
        end

        # parameter := '{' + name* + '}'
        parse_parameter = parse_between(
            NodeType::PARAMETER,
            TokenType::BEGIN_PARAMETER,
            TokenType::END_PARAMETER,
            [parse_name]
        )

        # optional := '(' + option* + ')'
        # option := optional | parameter | text
        optional_sub_parsers = []
        parse_optional = parse_between(
            NodeType::OPTIONAL,
            TokenType::BEGIN_OPTIONAL,
            TokenType::END_OPTIONAL,
            optional_sub_parsers
        )
        optional_sub_parsers << parse_optional << parse_parameter << parse_text

        # alternation := alternative* + ( '/' + alternative* )+
        parse_alternative_separator = lambda do |_, tokens, current|
          unless looking_at(tokens, current, TokenType::ALTERNATION)
            return 0, nil
          end
          token = tokens[current]
          return 1, [Node.new(NodeType::ALTERNATIVE, nil, token.text, token.start, token.end)]
        end

        alternative_parsers = [
            parse_alternative_separator,
            parse_optional,
            parse_parameter,
            parse_text,
        ]

        # alternation := (?<=left-boundary) + alternative* + ( '/' + alternative* )+ + (?=right-boundary)
        # left-boundary := whitespace | } | ^
        # right-boundary := whitespace | { | $
        # alternative: = optional | parameter | text
        parse_alternation = lambda do |expr, tokens, current|
          previous = current - 1
          unless looking_at_any(tokens, previous, [TokenType::START_OF_LINE, TokenType::WHITE_SPACE, TokenType::END_PARAMETER])
            return 0, nil
          end

          consumed, ast = parse_tokens_until(expr, alternative_parsers, tokens, current, [TokenType::WHITE_SPACE, TokenType::END_OF_LINE, TokenType::BEGIN_PARAMETER])
          sub_current = current + consumed
          unless ast.map { |astNode| astNode.type }.include? NodeType::ALTERNATIVE
            return 0, nil
          end

          start = tokens[current].start
          _end = tokens[sub_current].start
          # Does not consume right hand boundary token
          return consumed, [Node.new(NodeType::ALTERNATION, split_alternatives(start, _end, ast), nil, start, _end)]
        end

        #
        # cucumber-expression :=  ( alternation | optional | parameter | text )*
        #
        parse_cucumber_expression = parse_between(
            NodeType::EXPRESSION,
            TokenType::START_OF_LINE,
            TokenType::END_OF_LINE,
            [parse_alternation, parse_optional, parse_parameter, parse_text]
        )

        tokenizer = CucumberExpressionTokenizer.new
        tokens = tokenizer.tokenize(expression)
        _, ast = parse_cucumber_expression.call(expression, tokens, 0)
        ast[0]
      end

      private

      def parse_between(type, begin_token, end_token, parsers)
        lambda do |expression, tokens, current|
          unless looking_at(tokens, current, begin_token)
            return 0, nil
          end
          sub_current = current + 1
          consumed, ast = parse_tokens_until(expression, parsers, tokens, sub_current, [end_token, TokenType::END_OF_LINE])
          sub_current += consumed

          # endToken not found
          unless looking_at(tokens, sub_current, end_token)
            raise MissingEndToken.new(expression, begin_token, end_token, tokens[current])
          end
          # consumes endToken
          start = tokens[current].start
          _end = tokens[sub_current].end
          consumed = sub_current + 1 - current
          ast = [Node.new(type, ast, nil, start, _end)]
          return consumed, ast
        end
      end

      def parse_token(expression, parsers, tokens, start_at)
        parsers.each do |parser|
          consumed, ast = parser.call(expression, tokens, start_at)
          return consumed, ast unless consumed == 0
        end
        # If configured correctly this will never happen
        raise 'No eligible parsers for ' + tokens
      end

      def parse_tokens_until(expression, parsers, tokens, start_at, end_tokens)
        current = start_at
        size = tokens.length
        ast = []
        while current < size do
          if looking_at_any(tokens, current, end_tokens)
            break
          end
          consumed, sub_ast = parse_token(expression, parsers, tokens, current)
          if consumed == 0
            # If configured correctly this will never happen
            # Keep to avoid infinite loops
            raise 'No eligible parsers for ' + tokens
          end
          current += consumed
          ast += sub_ast
        end
        [current - start_at, ast]
      end

      def looking_at_any(tokens, at, token_types)
        token_types.detect { |token_type| looking_at(tokens, at, token_type) }
      end

      def looking_at(tokens, at, token)
        if at < 0
          # If configured correctly this will never happen
          # Keep for completeness
          return token == TokenType::START_OF_LINE
        end
        if at >= tokens.length
          return token == TokenType::END_OF_LINE
        end
        tokens[at].type == token
      end

      def split_alternatives(start, _end, alternation)
        separators = []
        alternatives = []
        alternative = []
        alternation.each { |n|
          if NodeType::ALTERNATIVE == n.type
            separators.push(n)
            alternatives.push(alternative)
            alternative = []
          else
            alternative.push(n)
          end
        }
        alternatives.push(alternative)
        create_alternative_nodes(start, _end, separators, alternatives)
      end

      def create_alternative_nodes(start, _end, separators, alternatives)
        alternatives.each_with_index.map do |n, i|
          if i == 0
            right_separator = separators[i]
            Node.new(NodeType::ALTERNATIVE, n, nil, start, right_separator.start)
          elsif i == alternatives.length - 1
            left_separator = separators[i - 1]
            Node.new(NodeType::ALTERNATIVE, n, nil, left_separator.end, _end)
          else
            left_separator = separators[i - 1]
            right_separator = separators[i]
            Node.new(NodeType::ALTERNATIVE, n, nil, left_separator.end, right_separator.start)
          end
        end
      end
    end
  end
end
