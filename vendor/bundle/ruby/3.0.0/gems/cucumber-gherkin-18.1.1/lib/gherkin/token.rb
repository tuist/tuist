module Gherkin
  class Token < Struct.new(:line, :location)
    attr_accessor :matched_type, :matched_text, :matched_keyword, :matched_indent,
                  :matched_items, :matched_gherkin_dialect

    def eof?
      line.nil?
    end

    def detach
      # TODO: detach line - is this needed?
    end

    def token_value
      eof? ? "EOF" : line.get_line_text(-1)
    end
  end
end
