require 'cli/ui/frame'

module CLI
  module UI
    module Frame
      module FrameStyle
        class << self
          # rubocop:disable Style/ClassVars
          @@loaded_styles = []

          def loaded_styles
            @@loaded_styles.map(&:name)
          end

          # Lookup a frame style via its name
          #
          # ==== Attributes
          #
          # * +symbol+ - frame style name to lookup
          def lookup(name)
            @@loaded_styles
              .find { |style| style.name.to_sym == name }
              .tap  { |style| raise InvalidFrameStyleName, name if style.nil? }
          end

          def extended(base)
            @@loaded_styles << base
            base.extend(Interface)
          end
          # rubocop:enable Style/ClassVars
        end

        class InvalidFrameStyleName < ArgumentError
          def initialize(name)
            super
            @name = name
          end

          def message
            keys = FrameStyle.loaded_styles.map(&:inspect).join(',')
            "invalid frame style: #{@name.inspect}" \
              ' -- must be one of CLI::UI::Frame::FrameStyle.loaded_styles ' \
              "(#{keys})"
          end
        end

        # Public interface for FrameStyles
        # Applied by extending FrameStyle
        module Interface
          def name
            raise NotImplementedError
          end

          # Returns the character(s) that should be printed at the beginning
          # of lines inside this frame
          def prefix
            raise NotImplementedError
          end

          # Returns the printing width of the prefix
          def prefix_width
            CLI::UI::ANSI.printing_width(prefix)
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
          def open(text, color:)
            raise NotImplementedError
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
          def close(text, color:, right_text: nil)
            raise NotImplementedError
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
          def divider(text, color: nil)
            raise NotImplementedError
          end

          private

          def print_at_x(x, str)
            CLI::UI::ANSI.cursor_horizontal_absolute(1 + x) + str
          end
        end
      end
    end
  end
end

require 'cli/ui/frame/frame_style/box'
require 'cli/ui/frame/frame_style/bracket'
