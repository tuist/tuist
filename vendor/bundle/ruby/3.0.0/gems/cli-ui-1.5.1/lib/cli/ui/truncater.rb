# frozen_string_literal: true

require 'cli/ui'

module CLI
  module UI
    # Truncater truncates a string to a provided printable width.
    module Truncater
      PARSE_ROOT = :root
      PARSE_ANSI = :ansi
      PARSE_ESC  = :esc
      PARSE_ZWJ  = :zwj

      ESC                 = 0x1b
      LEFT_SQUARE_BRACKET = 0x5b
      ZWJ                 = 0x200d # emojipedia.org/emoji-zwj-sequences
      SEMICOLON           = 0x3b

      # EMOJI_RANGE in particular is super inaccurate. This is best-effort.
      # If you need this to be more accurate, we'll almost certainly accept a
      # PR improving it.
      EMOJI_RANGE    = 0x1f300..0x1f5ff
      NUMERIC_RANGE  = 0x30..0x39
      LC_ALPHA_RANGE = 0x40..0x5a
      UC_ALPHA_RANGE = 0x60..0x71

      TRUNCATED = "\x1b[0m…"

      class << self
        def call(text, printing_width)
          return text if text.size <= printing_width

          width            = 0
          mode             = PARSE_ROOT
          truncation_index = nil

          codepoints = text.codepoints
          codepoints.each.with_index do |cp, index|
            case mode
            when PARSE_ROOT
              case cp
              when ESC # non-printable, followed by some more non-printables.
                mode = PARSE_ESC
              when ZWJ # non-printable, followed by another non-printable.
                mode = PARSE_ZWJ
              else
                width += width(cp)
                if width >= printing_width
                  truncation_index ||= index
                  # it looks like we could break here but we still want the
                  # width calculation for the rest of the characters.
                end
              end
            when PARSE_ESC
              mode = case cp
              when LEFT_SQUARE_BRACKET
                PARSE_ANSI
              else
                PARSE_ROOT
              end
            when PARSE_ANSI
              # ANSI escape codes preeeetty much have the format of:
              # \x1b[0-9;]+[A-Za-z]
              case cp
              when NUMERIC_RANGE, SEMICOLON
              when LC_ALPHA_RANGE, UC_ALPHA_RANGE
                mode = PARSE_ROOT
              else
                # unexpected. let's just go back to the root state I guess?
                mode = PARSE_ROOT
              end
            when PARSE_ZWJ
              # consume any character and consider it as having no width
              # width(x+ZWJ+y) = width(x).
              mode = PARSE_ROOT
            end
          end

          # Without the `width <= printing_width` check, we truncate
          # "foo\x1b[0m" for a width of 3, but it should not be truncated.
          # It's specifically for the case where we decided "Yes, this is the
          # point at which we'd have to add a truncation!" but it's actually
          # the end of the string.
          return text if !truncation_index || width <= printing_width

          codepoints[0...truncation_index].pack('U*') + TRUNCATED
        end

        private

        def width(printable_codepoint)
          case printable_codepoint
          when EMOJI_RANGE
            2
          else
            1
          end
        end
      end
    end
  end
end
