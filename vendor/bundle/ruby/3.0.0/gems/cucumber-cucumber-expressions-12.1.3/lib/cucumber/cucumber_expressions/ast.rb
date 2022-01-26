module Cucumber
  module CucumberExpressions
    ESCAPE_CHARACTER = '\\'
    ALTERNATION_CHARACTER = '/'
    BEGIN_PARAMETER_CHARACTER = '{'
    END_PARAMETER_CHARACTER = '}'
    BEGIN_OPTIONAL_CHARACTER = '('
    END_OPTIONAL_CHARACTER = ')'

    class Node
      def initialize(type, nodes, token, start, _end)
        if nodes.nil? && token.nil?
          raise 'Either nodes or token must be defined'
        end
        @type = type
        @nodes = nodes
        @token = token
        @start = start
        @end = _end
      end

      def type
        @type
      end

      def nodes
        @nodes
      end

      def token
        @token
      end

      def start
        @start
      end

      def end
        @end
      end

      def text
        if @token.nil?
          return @nodes.map { |value| value.text }.join('')
        end
        @token
      end

      def to_hash
        hash = Hash.new
        hash["type"] = @type
        unless @nodes.nil?
          hash["nodes"] = @nodes.map { |node| node.to_hash }
        end
        unless @token.nil?
          hash["token"] = @token
        end
        hash["start"] = @start
        hash["end"] = @end
        hash
      end
    end

    module NodeType
      TEXT = 'TEXT_NODE'
      OPTIONAL = 'OPTIONAL_NODE'
      ALTERNATION = 'ALTERNATION_NODE'
      ALTERNATIVE = 'ALTERNATIVE_NODE'
      PARAMETER = 'PARAMETER_NODE'
      EXPRESSION = 'EXPRESSION_NODE'
    end


    class Token
      def initialize(type, text, start, _end)
        @type, @text, @start, @end = type, text, start, _end
      end

      def type
        @type
      end

      def text
        @text
      end

      def start
        @start
      end

      def end
        @end
      end

      def self.is_escape_character(codepoint)
        codepoint.chr(Encoding::UTF_8) == ESCAPE_CHARACTER
      end

      def self.can_escape(codepoint)
        c = codepoint.chr(Encoding::UTF_8)
        if c == ' '
          # TODO: Unicode whitespace?
          return true
        end
        case c
        when ESCAPE_CHARACTER
          true
        when ALTERNATION_CHARACTER
          true
        when BEGIN_PARAMETER_CHARACTER
          true
        when END_PARAMETER_CHARACTER
          true
        when BEGIN_OPTIONAL_CHARACTER
          true
        when END_OPTIONAL_CHARACTER
          true
        else
          false
        end
      end

      def self.type_of(codepoint)
        c = codepoint.chr(Encoding::UTF_8)
        if c == ' '
          # TODO: Unicode whitespace?
          return TokenType::WHITE_SPACE
        end
        case c
        when ALTERNATION_CHARACTER
          TokenType::ALTERNATION
        when BEGIN_PARAMETER_CHARACTER
          TokenType::BEGIN_PARAMETER
        when END_PARAMETER_CHARACTER
          TokenType::END_PARAMETER
        when BEGIN_OPTIONAL_CHARACTER
          TokenType::BEGIN_OPTIONAL
        when END_OPTIONAL_CHARACTER
          TokenType::END_OPTIONAL
        else
          TokenType::TEXT
        end
      end

      def self.symbol_of(token)
        case token
        when TokenType::BEGIN_OPTIONAL
          return BEGIN_OPTIONAL_CHARACTER
        when TokenType::END_OPTIONAL
          return END_OPTIONAL_CHARACTER
        when TokenType::BEGIN_PARAMETER
          return BEGIN_PARAMETER_CHARACTER
        when TokenType::END_PARAMETER
          return END_PARAMETER_CHARACTER
        when TokenType::ALTERNATION
          return ALTERNATION_CHARACTER
        else
          return ''
        end
      end

      def self.purpose_of(token)
        case token
        when TokenType::BEGIN_OPTIONAL
          return 'optional text'
        when TokenType::END_OPTIONAL
          return 'optional text'
        when TokenType::BEGIN_PARAMETER
          return 'a parameter'
        when TokenType::END_PARAMETER
          return 'a parameter'
        when TokenType::ALTERNATION
          return 'alternation'
        else
          return ''
        end
      end

      def to_hash
        {
            "type" => @type,
            "text" => @text,
            "start" => @start,
            "end" => @end
        }
      end
    end

    module TokenType
      START_OF_LINE = 'START_OF_LINE'
      END_OF_LINE = 'END_OF_LINE'
      WHITE_SPACE = 'WHITE_SPACE'
      BEGIN_OPTIONAL = 'BEGIN_OPTIONAL'
      END_OPTIONAL = 'END_OPTIONAL'
      BEGIN_PARAMETER = 'BEGIN_PARAMETER'
      END_PARAMETER = 'END_PARAMETER'
      ALTERNATION = 'ALTERNATION'
      TEXT = 'TEXT'
    end
  end
end
