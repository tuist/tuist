require 'stringio'
require_relative 'token'
require_relative 'gherkin_line'

module Gherkin
  # The scanner reads a gherkin doc (typically read from a .feature file) and
  # creates a token for line. The tokens are passed to the parser, which outputs
  # an AST (Abstract Syntax Tree).
  #
  # If the scanner sees a # language header, it will reconfigure itself dynamically
  # to look for Gherkin keywords for the associated language. The keywords are defined
  # in gherkin-languages.json.
  class TokenScanner
    def initialize(source_or_io)
      @line_number = 0

      case(source_or_io)
      when String
        @io = StringIO.new(source_or_io)
      when StringIO, IO
        @io = source_or_io
      else
        fail ArgumentError, "Please a pass String, StringIO or IO. I got a #{source_or_io.class}"
      end
    end

    def read
      location = {line: @line_number += 1, column: 0}
      if @io.nil? || line = @io.gets
        gherkin_line = line ? GherkinLine.new(line, location[:line]) : nil
        Token.new(gherkin_line, location)
      else
        @io.close unless @io.closed? # ARGF closes the last file after final gets
        @io = nil
        Token.new(nil, location)
      end
    end

  end
end
