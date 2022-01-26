require 'cucumber/tag_expressions/expressions.rb'

module Cucumber
  module TagExpressions
    # Ruby tag expression parser
    class Parser
      def initialize
        @expressions = []
        @operators = []

        @operator_types = {
          'or'  => { type: :binary_operator,    precedence: 0, assoc: :left },
          'and' => { type: :binary_operator,   precedence: 1, assoc: :left },
          'not' => { type: :unary_operator,   precedence: 2, assoc: :right },
          ')'   => { type: :close_paren,       precedence: -1 },
          '('   => { type: :open_paren,        precedence: 1 }
        }
      end

      def parse(infix_expression)
        process_tokens!(infix_expression)
        while @operators.any?
          raise 'Syntax error. Unmatched (' if @operators.last == '('
          push_expression(pop(@operators))
        end
        expression = pop(@expressions)
        @expressions.empty? ? expression : raise('Not empty')
      end

      private

      ############################################################################
      # Helpers
      #
      def assoc_of(token, value)
        @operator_types[token][:assoc] == value
      end

      def lower_precedence?(operation)
        (assoc_of(operation, :left) &&
         precedence(operation) <= precedence(@operators.last)) ||
          (assoc_of(operation, :right) &&
           precedence(operation) < precedence(@operators.last))
      end

      def operator?(token)
        @operator_types[token][:type] == :unary_operator ||
            @operator_types[token][:type] == :binary_operator
      end

      def precedence(token)
        @operator_types[token][:precedence]
      end

      def tokens(infix_expression)
        infix_expression.gsub(/(?<!\\)\(/, ' ( ').gsub(/(?<!\\)\)/, ' ) ').strip.split(/\s+/)
      end

      def process_tokens!(infix_expression)
        expected_token_type = :operand
        tokens(infix_expression).each do |token|
          if @operator_types[token]
            expected_token_type = send("handle_#{@operator_types[token][:type]}", token, expected_token_type)
          else
            expected_token_type = handle_literal(token, expected_token_type)
          end
        end
      end

      def push_expression(token)
        case token
        when 'and'
          @expressions.push(And.new(*pop(@expressions, 2)))
        when 'or'
          @expressions.push(Or.new(*pop(@expressions, 2)))
        when 'not'
          @expressions.push(Not.new(pop(@expressions)))
        else
          @expressions.push(Literal.new(token))
        end
      end

      ############################################################################
      # Handlers
      #
      def handle_unary_operator(token, expected_token_type)
        check(expected_token_type, :operand)
        @operators.push(token)
        :operand
      end

      def handle_binary_operator(token, expected_token_type)
        check(expected_token_type, :operator)
        while @operators.any? && operator?(@operators.last) &&
              lower_precedence?(token)
          push_expression(pop(@operators))
        end
        @operators.push(token)
        :operand
      end

      def handle_open_paren(token, expected_token_type)
        check(expected_token_type, :operand)
        @operators.push(token)
        :operand
      end

      def handle_close_paren(_token, expected_token_type)
        check(expected_token_type, :operator)
        while @operators.any? && @operators.last != '('
          push_expression(pop(@operators))
        end
        raise 'Syntax error. Unmatched )' if @operators.empty?
        pop(@operators) if @operators.last == '('
        :operator
      end

      def handle_literal(token, expected_token_type)
        check(expected_token_type, :operand)
        push_expression(token)
        :operator
      end

      def check(expected_token_type, token_type)
        if expected_token_type != token_type
          raise "Syntax error. Expected #{expected_token_type}"
        end
      end

      def pop(array, n = 1)
        result = array.pop(n)
        raise('Empty stack') if result.size != n
        n == 1 ? result.first : result
      end
    end
  end
end
