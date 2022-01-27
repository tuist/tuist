module CLI
  module UI
    module Frame
      module FrameStyle
        module Bracket
          extend FrameStyle

          VERTICAL    = '┃'
          HORIZONTAL  = '━'
          DIVIDER     = '┣'
          TOP_LEFT    = '┏'
          BOTTOM_LEFT = '┗'

          class << self
            def name
              'bracket'
            end

            def prefix
              VERTICAL
            end

            # Draws the "Open" line for this frame style
            #
            # ==== Attributes
            #
            # * +text+ - (required) the text/title to output in the frame
            #
            # ==== Options
            #
            # * +:color+ - (required) The color of the frame.
            #
            # ==== Output
            #
            #   ┏━━ Open
            #
            def open(text, color:)
              edge(text, color: color, first: TOP_LEFT)
            end

            # Draws a "divider" line for the current frame style
            #
            # ==== Attributes
            #
            # * +text+ - (required) the text/title to output in the frame
            #
            # ==== Options
            #
            # * +:color+ - (required) The color of the frame.
            #
            # ==== Output:
            #
            #   ┣━━ Divider
            #
            def divider(text, color:)
              edge(text, color: color, first: DIVIDER)
            end

            # Draws the "Close" line for this frame style
            #
            # ==== Attributes
            #
            # * +text+ - (required) the text/title to output in the frame
            #
            # ==== Options
            #
            # * +:color+ - (required) The color of the frame.
            # * +:right_text+ - Text to print at the right of the line. Defaults to nil
            #
            # ==== Output:
            #
            #   ┗━━ Close
            #
            def close(text, color:, right_text: nil)
              edge(text, color: color, right_text: right_text, first: BOTTOM_LEFT)
            end

            private

            def edge(text, color:, first:, right_text: nil)
              color = CLI::UI.resolve_color(color)

              preamble = +''

              preamble << color.code << first << (HORIZONTAL * 2)

              text ||= ''
              unless text.empty?
                preamble << ' ' << CLI::UI.resolve_text("{{#{color.name}:#{text}}}") << ' '
              end

              suffix = +''

              if right_text
                suffix << ' ' << right_text << ' '
              end

              o = +''

              # Shopify's CI system supports terminal emulation, but not some of
              # the fancier features that we normally use to draw frames
              # extra-reliably, so we fall back to a less foolproof strategy. This
              # is probably better in general for cases with impoverished terminal
              # emulators and no active user.
              unless [0, '', nil].include?(ENV['CI'])
                o << color.code << preamble
                o << color.code << suffix
                o << CLI::UI::Color::RESET.code
                o << "\n"

                return o
              end

              preamble_start = Frame.prefix_width

              # If prefix_width is non-zero, we need to subtract the width of
              # the final space, since we're going to write over it.
              preamble_start -= 1 unless preamble_start.zero?

              # Prefix_width includes the width of the terminal space, which we
              # want to remove.  The clamping is done to avoid a negative
              # preamble start which can occur for the first frame.
              o << CLI::UI::ANSI.hide_cursor

              # reset to column 1 so that things like ^C don't ruin formatting
              o << "\r"
              o << color.code
              o << print_at_x(preamble_start, preamble + color.code + suffix)
              o << CLI::UI::Color::RESET.code
              o << "\n"

              o
            end
          end
        end
      end
    end
  end
end
