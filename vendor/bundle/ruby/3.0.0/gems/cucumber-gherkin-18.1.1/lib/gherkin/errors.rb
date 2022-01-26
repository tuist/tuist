module Gherkin
  class ParserError < StandardError; end
  class AstNodeNotLocatedException < StandardError; end
  class DoubleIterationException < StandardError; end

  class ParserException < ParserError
    attr_reader :location

    def initialize(message, location)
      @location = location
      super("(#{location[:line]}:#{location[:column] || 0}): #{message}")
    end
  end

  class NoSuchLanguageException < ParserException
    def initialize(language, location)
      super "Language not supported: #{language}", location
    end
  end

  class AstBuilderException < ParserException; end

  class CompositeParserException < ParserError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super "Parser errors:\n" + errors.map(&:message).join("\n")
    end
  end

  class UnexpectedTokenException < ParserException
    def initialize(received_token, expected_token_types, state_comment)
      message = "expected: #{expected_token_types.join(", ")}, got '#{received_token.token_value.strip}'"
      column = received_token.location[:column]
      location =  (column.nil? || column.zero?) ? {line: received_token.location[:line], column: received_token.line.indent + 1} : received_token.location
      super(message, location)
    end
  end

  class UnexpectedEOFException < ParserException
    def initialize(received_token, expected_token_types, state_comment)
      message = "unexpected end of file, expected: #{expected_token_types.join(", ")}"
      super(message, received_token.location)
    end
  end
end
