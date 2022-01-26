require_relative 'dialect'
require_relative 'errors'

module Gherkin
  class TokenMatcher
    LANGUAGE_PATTERN = /^\s*#\s*language\s*:\s*([a-zA-Z\-_]+)\s*$/

    def initialize(dialect_name = 'en')
      @default_dialect_name = dialect_name
      change_dialect(dialect_name, nil)
      reset
    end

    def reset
      change_dialect(@default_dialect_name, nil) unless @dialect_name == @default_dialect_name
      @active_doc_string_separator = nil
      @indent_to_remove = 0
    end

    def match_TagLine(token)
      return false unless token.line.start_with?('@')

      set_token_matched(token, :TagLine, nil, nil, nil, token.line.tags)
      true
    end

    def match_FeatureLine(token)
      match_title_line(token, :FeatureLine, @dialect.feature_keywords)
    end

    def match_RuleLine(token)
      match_title_line(token, :RuleLine, @dialect.rule_keywords)
    end

    def match_ScenarioLine(token)
      match_title_line(token, :ScenarioLine, @dialect.scenario_keywords) ||
          match_title_line(token, :ScenarioLine, @dialect.scenario_outline_keywords)
    end

    def match_BackgroundLine(token)
      match_title_line(token, :BackgroundLine, @dialect.background_keywords)
    end

    def match_ExamplesLine(token)
      match_title_line(token, :ExamplesLine, @dialect.examples_keywords)
    end

    def match_TableRow(token)
      return false unless token.line.start_with?('|')
      # TODO: indent
      set_token_matched(token, :TableRow, nil, nil, nil, token.line.table_cells)
      true
    end

    def match_Empty(token)
      return false unless token.line.empty?
      set_token_matched(token, :Empty, nil, nil, 0)
      true
    end

    def match_Comment(token)
      return false unless token.line.start_with?('#')
      text = token.line.get_line_text(0) #take the entire line, including leading space
      set_token_matched(token, :Comment, text, nil, 0)
      true
    end

    def match_Language(token)
      return false unless token.line.trimmed_line_text =~ LANGUAGE_PATTERN

      dialect_name = $1
      set_token_matched(token, :Language, dialect_name)

      change_dialect(dialect_name, token.location)

      true
    end

    def match_DocStringSeparator(token)
      if @active_doc_string_separator.nil?
        # open
        _match_DocStringSeparator(token, '"""', true) ||
            _match_DocStringSeparator(token, '```', true)
      else
        # close
        _match_DocStringSeparator(token, @active_doc_string_separator, false)
      end
    end

    def _match_DocStringSeparator(token, separator, is_open)
      return false unless token.line.start_with?(separator)

      media_type = nil
      if is_open
        media_type = token.line.get_rest_trimmed(separator.length)
        @active_doc_string_separator = separator
        @indent_to_remove = token.line.indent
      else
        @active_doc_string_separator = nil
        @indent_to_remove = 0
      end

      set_token_matched(token, :DocStringSeparator, media_type, separator)
      true
    end

    def match_EOF(token)
      return false unless token.eof?
      set_token_matched(token, :EOF)
      true
    end

    def match_Other(token)
      text = token.line.get_line_text(@indent_to_remove) # take the entire line, except removing DocString indents
      set_token_matched(token, :Other, unescape_docstring(text), nil, 0)
      true
    end

    def match_StepLine(token)
      keywords = @dialect.given_keywords +
          @dialect.when_keywords +
          @dialect.then_keywords +
          @dialect.and_keywords +
          @dialect.but_keywords

      keyword = keywords.detect { |k| token.line.start_with?(k) }

      return false unless keyword

      title = token.line.get_rest_trimmed(keyword.length)
      set_token_matched(token, :StepLine, title, keyword)
      return true
    end

    private

    def change_dialect(dialect_name, location)
      dialect = Dialect.for(dialect_name)
      raise NoSuchLanguageException.new(dialect_name, location) if dialect.nil?

      @dialect_name = dialect_name
      @dialect = dialect
    end

    def match_title_line(token, token_type, keywords)
      keyword = keywords.detect { |k| token.line.start_with_title_keyword?(k) }

      return false unless keyword

      title = token.line.get_rest_trimmed(keyword.length + ':'.length)
      set_token_matched(token, token_type, title, keyword)
      true
    end

    def set_token_matched(token, matched_type, text = nil, keyword = nil, indent = nil, items = [])
      token.matched_type = matched_type
      token.matched_text = text && text.chomp
      token.matched_keyword = keyword
      token.matched_indent = indent || (token.line && token.line.indent) || 0
      token.matched_items = items
      token.location[:column] = token.matched_indent + 1
      token.matched_gherkin_dialect = @dialect_name
    end

    def unescape_docstring(text)
      if @active_doc_string_separator == "\"\"\""
        text.gsub("\\\"\\\"\\\"", "\"\"\"")
      elsif @active_doc_string_separator == "```"
        text.gsub("\\`\\`\\`", "```")
      else
        text
      end
    end
  end
end
