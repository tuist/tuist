module Gherkin
  class TokenFormatterBuilder
    def initialize
      reset
    end

    def reset
      @tokens_text = ""
    end

    def build(token)
      @tokens_text << "#{format_token(token)}\n"
    end

    def start_rule(rule_type)
    end

    def end_rule(rule_type)
    end

    def get_result
      @tokens_text
    end

    private
    def format_token(token)
      return "EOF" if token.eof?

      sprintf "(%s:%s)%s:%s/%s/%s",
        token.location[:line],
        token.location[:column],
        token.matched_type,
        token.matched_keyword,
        token.matched_text,
        Array(token.matched_items).map { |i| "#{i.column}:#{i.text}"}.join(',')
    end

  end
end
