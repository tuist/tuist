require 'cucumber/term/ansicolor'

module Cucumber
  module Term
    module Banner
      def display_banner(lines, io, border_modifiers = nil)
        BannerMaker.new.display_banner(lines, io, border_modifiers || %i[green bold])
      end

      class BannerMaker
        include Term::ANSIColor

        def display_banner(lines, io, border_modifiers)
          lines = lines.split("\n") if lines.is_a? String
          longest_line_length = lines.map { |line| line_length(line) }.max

          io.puts apply_modifiers("┌#{'─' * (longest_line_length + 2)}┐", border_modifiers)
          lines.map do |line|
            padding = ' ' * (longest_line_length - line_length(line))
            io.puts "#{apply_modifiers('│', border_modifiers)} #{display_line(line)}#{padding} #{apply_modifiers('│', border_modifiers)}"
          end
          io.puts apply_modifiers("└#{'─' * (longest_line_length + 2)}┘", border_modifiers)
        end

        private

        def display_line(line)
          line.is_a?(Array) ? line.map { |span| display_span(span) }.join : line
        end

        def display_span(span)
          return apply_modifiers(span.shift, span) if span.is_a?(Array)
          span
        end

        def apply_modifiers(str, modifiers)
          display = str
          modifiers.each { |modifier| display = send(modifier, display) }
          display
        end

        def line_length(line)
          if line.is_a?(Array)
            line.map { |span| span_length(span) }.sum
          else
            line.length
          end
        end

        def span_length(span)
          span.is_a?(Array) ? span[0].length : span.length
        end
      end
    end
  end
end
