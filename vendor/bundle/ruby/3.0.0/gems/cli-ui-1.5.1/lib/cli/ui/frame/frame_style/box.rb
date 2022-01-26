module CLI
  module UI
    module Frame
      module FrameStyle
        module Box
          extend FrameStyle

          VERTICAL    = '┃'
          HORIZONTAL  = '━'
          DIVIDER     = '┣'
          TOP_LEFT    = '┏'
          BOTTOM_LEFT = '┗'

          class << self
            def name
              'box'
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
            # ==== Output:
            #
            #   ┏━━ Open ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
            #   ┣━━ Divider ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
            #   ┗━━ Close ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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

              termwidth = CLI::UI::Terminal.width

              suffix = +''

              if right_text
                suffix << ' ' << right_text << ' '
              end

              preamble_width = CLI::UI::ANSI.printing_width(preamble)
              preamble_start = Frame.prefix_width
              # If prefix_width is non-zero, we need to subtract the width of
              # the final space, since we're going to write over it.
              preamble_start -= 1 unless preamble_start.zero?
              preamble_end = preamble_start + preamble_width

              suffix_width = CLI::UI::ANSI.printing_width(suffix)
              suffix_end   = termwidth - 2
              suffix_start = suffix_end - suffix_width

              if preamble_end > suffix_start
                suffix = ''
                # if preamble_end > termwidth
                # we *could* truncate it, but let's just let it overflow to the
                # next line and call it poor usage of this API.
              end

              o = +''

              # Shopify's CI system supports terminal emulation, but not some of
              # the fancier features that we normally use to draw frames
              # extra-reliably, so we fall back to a less foolproof strategy. This
              # is probably better in general for cases with impoverished terminal
              # emulators and no active user.
              unless [0, '', nil].include?(ENV['CI'])
                linewidth = [0, termwidth - (preamble_end + suffix_width + 1)].max

                o << color.code << preamble
                o << color.code << (HORIZONTAL * linewidth)
                o << color.code << suffix
                o << CLI::UI::Color::RESET.code << "\n"
                return o
              end

              # Jumping around the line can cause some unwanted flashes
              o << CLI::UI::ANSI.hide_cursor

              # reset to column 1 so that things like ^C don't ruin formatting
              o << "\r"

              # This code will print out a full line with the given preamble and
              # suffix, as exemplified below.
              #
              # preamble_start                         suffix_start
              # |                 preamble_end         |            suffix_end
              # |                 |                    |            | termwidth
              # |                 |                    |            | |
              # V                 V                    V            V V
              # --- Preamble text --------------------- suffix text --
              o << color.code
              o << print_at_x(preamble_start, HORIZONTAL * (termwidth - preamble_start)) # draw a full line
              o << print_at_x(preamble_start, preamble)
              o << color.code
              o << print_at_x(suffix_start, suffix)
              o << CLI::UI::Color::RESET.code
              o << CLI::UI::ANSI.show_cursor
              o << "\n"

              o
            end
          end
        end
      end
    end
  end
end
