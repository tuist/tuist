# frozen_string_literal: true
require('cli/ui')
require('strscan')

module CLI
  module UI
    class Formatter
      # Available mappings of formattings
      # To use any of them, you can use {{<key>:<string>}}
      # There are presentational (colours and formatters)
      # and semantic (error, info, command) formatters available
      #
      SGR_MAP = {
        # presentational
        'red' => '31',
        'green' => '32',
        'yellow' => '33',
        # default blue is low-contrast against black in some default terminal color scheme
        'blue' => '94', # 9x = high-intensity fg color x
        'magenta' => '35',
        'cyan' => '36',
        'bold' => '1',
        'italic' => '3',
        'underline' => '4',
        'reset' => '0',

        # semantic
        'error' => '31', # red
        'success' => '32', # success
        'warning' => '33', # yellow
        'info' => '94', # bright blue
        'command' => '36', # cyan
      }.freeze

      BEGIN_EXPR = '{{'
      END_EXPR   = '}}'

      SCAN_WIDGET   = %r[@widget/(?<handle>\w+):(?<args>.*?)}}]
      SCAN_FUNCNAME = /\w+:/
      SCAN_GLYPH    = /.}}/
      SCAN_BODY     = %r{
        .*?
        (
          #{BEGIN_EXPR} |
          #{END_EXPR}   |
          \z
        )
      }mx

      DISCARD_BRACES = 0..-3

      LITERAL_BRACES = :__literal_braces__

      class FormatError < StandardError
        attr_accessor :input, :index

        def initialize(message = nil, input = nil, index = nil)
          super(message)
          @input = input
          @index = index
        end
      end

      # Initialize a formatter with text.
      #
      # ===== Attributes
      #
      # * +text+ - the text to format
      #
      def initialize(text)
        @text = text
      end

      # Format the text using a map.
      #
      # ===== Attributes
      #
      # * +sgr_map+ - the mapping of the formattings. Defaults to +SGR_MAP+
      #
      # ===== Options
      #
      # * +:enable_color+ - enable color output? Default is true unless output is redirected
      #
      def format(sgr_map = SGR_MAP, enable_color: CLI::UI.enable_color?)
        @nodes = []
        stack = parse_body(StringScanner.new(@text))
        prev_fmt = nil
        content = @nodes.each_with_object(+'') do |(text, fmt), str|
          if prev_fmt != fmt && enable_color
            text = apply_format(text, fmt, sgr_map)
          end
          str << text
          prev_fmt = fmt
        end

        stack.reject! { |e| e == LITERAL_BRACES }

        return content unless enable_color
        return content if stack == prev_fmt

        unless stack.empty? && (@nodes.size.zero? || @nodes.last[1].empty?)
          content << apply_format('', stack, sgr_map)
        end
        content
      end

      private

      def apply_format(text, fmt, sgr_map)
        sgr = fmt.each_with_object(+'0') do |name, str|
          next if name == LITERAL_BRACES
          begin
            str << ';' << sgr_map.fetch(name)
          rescue KeyError
            raise FormatError.new(
              "invalid format specifier: #{name}",
              @text,
              -1
            )
          end
        end
        CLI::UI::ANSI.sgr(sgr) + text
      end

      def parse_expr(sc, stack)
        if (match = sc.scan(SCAN_GLYPH))
          glyph_handle = match[0]
          begin
            glyph = Glyph.lookup(glyph_handle)
            emit(glyph.char, [glyph.color.name.to_s])
          rescue Glyph::InvalidGlyphHandle
            index = sc.pos - 2 # rewind past '}}'
            raise FormatError.new(
              "invalid glyph handle at index #{index}: '#{glyph_handle}'",
              @text,
              index
            )
          end
        elsif (match = sc.scan(SCAN_WIDGET))
          match_data = SCAN_WIDGET.match(match) # Regexp.last_match doesn't work here
          widget_handle = match_data['handle']
          begin
            widget = Widgets.lookup(widget_handle)
            emit(widget.call(match_data['args']), stack)
          rescue Widgets::InvalidWidgetHandle
            index = sc.pos - 2 # rewind past '}}'
            raise(FormatError.new(
              "invalid widget handle at index #{index}: '#{widget_handle}'",
              @text, index,
            ))
          end
        elsif (match = sc.scan(SCAN_FUNCNAME))
          funcname = match.chop
          stack.push(funcname)
        else
          # We read a {{ but it's not apparently Formatter syntax.
          # We could error, but it's nicer to just pass through as text.
          # We do kind of assume that the text will probably have balanced
          # pairs of {{ }} at least.
          emit('{{', stack)
          stack.push(LITERAL_BRACES)
        end
        parse_body(sc, stack)
        stack
      end

      def parse_body(sc, stack = [])
        match = sc.scan(SCAN_BODY)
        if match&.end_with?(BEGIN_EXPR)
          emit(match[DISCARD_BRACES], stack)
          parse_expr(sc, stack)
        elsif match&.end_with?(END_EXPR)
          emit(match[DISCARD_BRACES], stack)
          if stack.pop == LITERAL_BRACES
            emit('}}', stack)
          end
          parse_body(sc, stack)
        elsif match
          emit(match, stack)
        else
          emit(sc.rest, stack)
        end
        stack
      end

      def emit(text, stack)
        return if text.nil? || text.empty?
        @nodes << [text, stack.reject { |n| n == LITERAL_BRACES }]
      end
    end
  end
end
