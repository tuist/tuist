module Gherkin
  class GherkinLine
    attr_reader :indent, :trimmed_line_text
    def initialize(line_text, line_number)
      @line_text = line_text
      @line_number = line_number
      @trimmed_line_text = @line_text.lstrip
      @indent = @line_text.length - @trimmed_line_text.length
    end

    def start_with?(prefix)
      @trimmed_line_text.start_with?(prefix)
    end

    def start_with_title_keyword?(keyword)
      start_with?(keyword+':') # The C# impl is more complicated. Find out why.
    end

    def get_rest_trimmed(length)
      @trimmed_line_text[length..-1].strip
    end

    def empty?
      @trimmed_line_text.empty?
    end

    def get_line_text(indent_to_remove)
      indent_to_remove ||= 0
      if indent_to_remove < 0 || indent_to_remove > indent
        @trimmed_line_text
      else
        @line_text[indent_to_remove..-1]
      end
    end

    def table_cells
      cells = []

      self.split_table_cells(@trimmed_line_text) do |item, column|
        # Keeps new lines
        txt_trimmed_left = item.sub(/\A[ \t\v\f\r\u0085\u00A0]*/, '')
        txt_trimmed = txt_trimmed_left.sub(/[ \t\v\f\r\u0085\u00A0]*\z/, '')
        cell_indent = item.length - txt_trimmed_left.length
        span = Span.new(@indent + column + cell_indent, txt_trimmed)
        cells.push(span)
      end

      cells
    end

    def split_table_cells(row)
      col = 0
      start_col = col + 1
      cell = ''
      first_cell = true
      while col < row.length
        char = row[col]
        col += 1
        if char == '|'
          if first_cell
            # First cell (content before the first |) is skipped
            first_cell = false
          else
            yield cell, start_col
          end
          cell = ''
          start_col = col + 1
        elsif char == '\\'
          char = row[col]
          col += 1
          if char == 'n'
            cell += "\n"
          else
            cell += '\\' unless ['|', '\\'].include?(char)
            cell += char
          end
        else
          cell += char
        end
      end
      # Last cell (content after the last |) is skipped
    end

    def tags
      uncommented_line = @trimmed_line_text.split(/\s#/,2)[0]
      column = @indent + 1
      items = uncommented_line.split('@')

      tags = []
      items.each { |untrimmed|
        item = untrimmed.strip
        if item.length == 0
          next
        end

        unless item =~ /^\S+$/
          location = {line: @line_number, column: column}
          raise ParserException.new('A tag may not contain whitespace', location)
        end

        tags << Span.new(column, '@' + item)
        column += untrimmed.length + 1
      }
      tags
    end

    class Span < Struct.new(:column, :text); end
  end
end
