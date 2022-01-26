require 'cli/ui'

module CLI
  module UI
    class Color
      attr_reader :sgr, :name, :code

      # Creates a new color mapping
      # Signatures can be found here:
      # https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
      #
      # ==== Attributes
      #
      # * +sgr+ - The color signature
      # * +name+ - The name of the color
      #
      def initialize(sgr, name)
        @sgr  = sgr
        @code = CLI::UI::ANSI.sgr(sgr)
        @name = name
      end

      RED     = new('31', :red)
      GREEN   = new('32', :green)
      YELLOW  = new('33', :yellow)
      # default blue is low-contrast against black in some default terminal color scheme
      BLUE    = new('94', :blue) # 9x = high-intensity fg color x
      MAGENTA = new('35', :magenta)
      CYAN    = new('36', :cyan)
      RESET   = new('0',  :reset)
      BOLD    = new('1',  :bold)
      WHITE   = new('97', :white)

      # 240 is very dark gray; 255 is very light gray. 244 is somewhat dark.
      GRAY = new('38;5;244', :grey)

      MAP = {
        red: RED,
        green: GREEN,
        yellow: YELLOW,
        blue: BLUE,
        magenta: MAGENTA,
        cyan: CYAN,
        reset: RESET,
        bold: BOLD,
        gray: GRAY,
      }.freeze

      class InvalidColorName < ArgumentError
        def initialize(name)
          super
          @name = name
        end

        def message
          keys = Color.available.map(&:inspect).join(',')
          "invalid color: #{@name.inspect} " \
            "-- must be one of CLI::UI::Color.available (#{keys})"
        end
      end

      # Looks up a color code by name
      #
      # ==== Raises
      # Raises a InvalidColorName if the color is not available
      # You likely need to add it to the +MAP+ or you made a typo
      #
      # ==== Returns
      # Returns a color code
      #
      def self.lookup(name)
        MAP.fetch(name)
      rescue KeyError
        raise InvalidColorName, name
      end

      # All available colors by name
      #
      def self.available
        MAP.keys
      end
    end
  end
end
