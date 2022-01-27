# coding: utf-8
require 'cli/ui'
require 'cli/ui/frame/frame_stack'
require 'cli/ui/frame/frame_style'

module CLI
  module UI
    class Wrap
      def initialize(input)
        @input = input
      end

      def wrap
        max_width = Terminal.width - Frame.prefix_width
        width = 0
        final = []
        # Create an alternation of format codes of parameter lengths 1-20, since + and {1,n} not allowed in lookbehind
        format_codes = (1..20).map { |n| /\x1b\[[\d;]{#{n}}m/ }.join('|')
        codes = ''
        @input.split(/(?=\s|\x1b\[[\d;]+m|\r)|(?<=\s|#{format_codes})/).each do |token|
          case token
          when '\x1B[0?m'
            codes = ''
            final << token
          when /\x1b\[[\d;]+m/
            codes += token # Track in use format codes so that they are resent after frame coloring
            final << token
          when "\n"
            final << "\n#{codes}"
            width = 0
          when /\s/
            token_width = ANSI.printing_width(token)
            if width + token_width <= max_width
              final << token
              width += token_width
            else
              final << "\n#{codes}"
              width = 0
            end
          else
            token_width = ANSI.printing_width(token)
            if width + token_width <= max_width
              final << token
              width += token_width
            else
              final << "\n#{codes}"
              final << token
              width = token_width
            end
          end
        end
        final.join
      end
    end
  end
end
