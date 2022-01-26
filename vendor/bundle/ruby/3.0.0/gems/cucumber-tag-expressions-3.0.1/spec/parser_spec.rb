require 'cucumber/tag_expressions/parser'

describe Cucumber::TagExpressions::Parser do
  correct_test_data = [
    ['a and b', '( a and b )'],
    ['a or (b)', '( a or b )'],
    ['not   a', 'not ( a )'],
    ['( a and b ) or ( c and d )', '( ( a and b ) or ( c and d ) )'],
    ['not a or b and not c or not d or e and f',
     '( ( ( not ( a ) or ( b and not ( c ) ) ) or not ( d ) ) or ( e and f ) )'],
    ['not a\\(\\) or b and not c or not d or e and f',
     '( ( ( not ( a\\(\\) ) or ( b and not ( c ) ) ) or not ( d ) ) or ( e and f ) )']
  ]

  error_test_data = [
    ['@a @b or', 'Syntax error. Expected operator'],
    ['@a and (@b not)', 'Syntax error. Expected operator'],
    ['@a and (@b @c) or', 'Syntax error. Expected operator'],
    ['@a and or', 'Syntax error. Expected operand'],
    ['or or', 'Syntax error. Expected operand'],
    ['a b', 'Syntax error. Expected operator'],
    ['( a and b ) )', 'Syntax error. Unmatched )'],
    ['( ( a and b )', 'Syntax error. Unmatched ('],
  ]

  context '#parse' do
    context 'with correct test data' do
      correct_test_data.each do |infix_expression, to_string|
        parser = Cucumber::TagExpressions::Parser.new
        it "parses correctly #{infix_expression.inspect}" do
          expect(parser.parse(infix_expression).to_s).to eq(to_string)
        end
      end
    end

    context 'with error test data' do
      error_test_data.each do |infix_expression, message|
        parser = Cucumber::TagExpressions::Parser.new
        it "raises an error parsing #{infix_expression.inspect}" do
          expect { parser.parse(infix_expression) }
            .to raise_error(RuntimeError, message)
        end
      end
    end
  end
end
