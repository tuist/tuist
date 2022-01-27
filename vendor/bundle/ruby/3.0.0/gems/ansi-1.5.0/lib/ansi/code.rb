module ANSI

  # Global variable can be used to prevent ANSI codes
  # from being used in ANSI's methods that do so to string.
  #
  # NOTE: This has no effect on methods that return ANSI codes.
  $ansi = true

  if RUBY_PLATFORM =~ /(win32|w32)/
    begin
      require 'Win32/Console/ANSI'
    rescue LoadError
      warn "ansi: 'gem install win32console' to use color on Windows"
      $ansi = false
    end
  end

  require 'ansi/constants'

  # TODO: up, down, right, left, etc could have yielding methods too?

  # ANSI Codes
  #
  # Ansi::Code module makes it very easy to use ANSI codes.
  # These are especially nice for beautifying shell output.
  #
  #   Ansi::Code.red + "Hello" + Ansi::Code.blue + "World"
  #   => "\e[31mHello\e[34mWorld"
  #
  #   Ansi::Code.red{ "Hello" } + Ansi::Code.blue{ "World" }
  #   => "\e[31mHello\e[0m\e[34mWorld\e[0m"
  #
  # IMPORTANT! Do not mixin Ansi::Code, instead use {ANSI::Mixin}.
  #
  # See {ANSI::CHART} for list of all supported codes.
  #
  module Code
    extend self

    # include ANSI Constants
    include Constants

    # Regexp for matching most ANSI codes.
    PATTERN = /\e\[(\d+)m/

    # ANSI clear code.
    ENDCODE = "\e[0m"

    # List of primary styles.
    def self.styles
      %w{bold dark italic underline underscore blink rapid reverse negative concealed strike}
    end

    # List of primary colors.
    def self.colors
      %w{black red green yellow blue magenta cyan white}
    end

    # Return ANSI code given a list of symbolic names.
    def [](*codes)
      code(*codes)
    end

    # Dynamically create color on color methods.
    #
    # @deprecated
    #
    colors.each do |color|
      colors.each do |on_color|
        module_eval <<-END, __FILE__, __LINE__
          def #{color}_on_#{on_color}(string=nil)
            if string
              return string unless $ansi
              #warn "use ANSI block notation for future versions"
              return #{color.upcase} + ON_#{color.upcase} + string + ENDCODE
            end
            if block_given?
              return yield unless $ansi
              #{color.upcase} + ON_#{on_color.upcase} + yield.to_s + ENDCODE
            else
              #{color.upcase} + ON_#{on_color.upcase}
            end
          end
        END
      end
    end

    # Use method missing to dispatch ANSI code methods.
    def method_missing(code, *args, &blk)
      esc = nil

      if CHART.key?(code)
        esc = "\e[#{CHART[code]}m"
      elsif SPECIAL_CHART.key?(code)
        esc = SPECIAL_CHART[code]
      end

      if esc
        if string = args.first
          return string unless $ansi
          #warn "use ANSI block notation for future versions"
          return "#{esc}#{string}#{ENDCODE}"
        end
        if block_given?
          return yield unless $ansi
          return "#{esc}#{yield}#{ENDCODE}"
        end
        esc
      else
        super(code, *args, &blk)
      end
    end

    # TODO: How to deal with position codes when $ansi is false?
    # Should we raise an error or just not push the codes?
    # For now, we will leave this it as is.

    # Like +move+ but returns to original position after
    # yielding the block.
    def display(line, column=0) #:yield:
      result = "\e[s"
      result << "\e[#{line.to_i};#{column.to_i}H"
      if block_given?
        result << yield
        result << "\e[u"
      #elsif string
      #  result << string
      #  result << "\e[u"
      end
      result
    end

    # Move cursor to line and column.
    def move(line, column=0)
      "\e[#{line.to_i};#{column.to_i}H"
    end

    # Move cursor up a specified number of spaces.
    def up(spaces=1)
      "\e[#{spaces.to_i}A"
    end

    # Move cursor down a specified number of spaces.
    def down(spaces=1)
      "\e[#{spaces.to_i}B"
    end

    # Move cursor left a specified number of spaces.
    def left(spaces=1)
      "\e[#{spaces.to_i}D"
    end
    alias :back :left

    # Move cursor right a specified number of spaces.
    def right(spaces=1)
      "\e[#{spaces.to_i}C"
    end
    alias :forward :right

    ##
    #def position
    #  "\e[#;#R"
    #end

    # Apply ANSI codes to a first argument or block value.
    #
    # @example
    #   ansi("Valentine", :red, :on_white)
    #
    # @example
    #   ansi(:red, :on_white){ "Valentine" }
    #
    # @return [String]
    #   String wrapped ANSI code.
    #
    def ansi(*codes) #:yield:
      if block_given?
        string = yield.to_s
      else
        # first argument must be the string
        string = codes.shift.to_s
      end

      return string unless $ansi

      c = code(*codes)

      c + string.gsub(ENDCODE, ENDCODE + c) + ENDCODE
    end

    # TODO: Allow selective removal using *codes argument?

    # Remove ANSI codes from string or block value.
    #
    # @param [String] string
    #   String from which to remove ANSI codes.
    #
    # @return [String]
    #   String wrapped ANSI code.
    #
    def unansi(string=nil) #:yield:
      if block_given?
        string = yield.to_s
      else
        string = string.to_s
      end
      string.gsub(PATTERN, '')
    end

    # Alias for #ansi method.
    #
    # @deprecated
    #   Here for backward compatibility.
    alias_method :style, :ansi

    # Alias for #unansi method.
    #
    # @deprecated 
    #   Here for backwards compatibility.
    alias_method :unstyle, :unansi

    # Alternate term for #ansi.
    #
    # @deprecated 
    #   May change in future definition.
    alias_method :color, :ansi

    # Alias for unansi.
    #
    # @deprecated 
    #   May change in future definition.
    alias_method :uncolor, :unansi

    # Look-up code from chart, or if Integer simply pass through.
    # Also resolves :random and :on_random.
    #
    # @param codes [Array<Symbol,Integer]
    #   Symbols or integers to convert to ANSI code.
    #
    # @return [String] ANSI code
    def code(*codes)
      list = []
      codes.each do |code|
        list << \
          case code
          when Integer
            code
          when Array
            rgb_code(*code)
          when :random, 'random'
            random
          when :on_random, 'on_random'
            random(true)
          when String
            # TODO: code =~ /\d\d\d\d\d\d/ ?
            if code.start_with?('#')
              hex_code(code)
            else
              CHART[code.to_sym]
            end
          else
            CHART[code.to_sym]
          end
      end
      "\e[" + (list * ";") + "m"
    end

    # Provides a random primary ANSI color.
    #
    # @param background [Boolean]
    #   Use `true` for background color, otherwise foreground color.
    #
    # @return [Integer] ANSI color number
    def random(background=false)
      (background ? 40 : 30) + rand(8)
    end

    # Creates an XTerm 256 color escape code from RGB value(s). The
    # RGB value can be three arguments red, green and blue respectively
    # each from 0 to 255, or the RGB value can be a single CSS-style
    # hex string.
    #
    # @param background [Boolean]
    #   Use `true` for background color, otherwise foreground color.
    #
    def rgb(*args)
      case args.size
      when 1, 2
        hex, background = *args
        esc = "\e[" + hex_code(hex, background) + "m"
      when 3, 4
        red, green, blue, background = *args
        esc = "\e[" + rgb_code(red, green, blue, background) + "m"
      else
        raise ArgumentError
      end

      if block_given?
        return yield.to_s unless $ansi
        return "#{esc}#{yield}#{ENDCODE}"
      else
        return esc
      end
    end

  #private

    # Creates an xterm-256 color from rgb value.
    #
    # @param background [Boolean]
    #   Use `true` for background color, otherwise foreground color.
    #
    def rgb_code(red, green, blue, background=false)
      "#{background ? 48 : 38};5;#{rgb_256(red, green, blue)}"
    end

    # Creates an xterm-256 color code from a CSS-style color string.
    #
    # @param string [String]
    #   Hex string in CSS style, .e.g. `#5FA0C2`.
    #
    # @param background [Boolean]
    #   Use `true` for background color, otherwise foreground color.
    #
    def hex_code(string, background=false)
      string.tr!('#','')
      x = (string.size == 6 ? 2 : 1)
      r, g, b = [0,1,2].map{ |i| string[i*x,2].to_i(16) }
      rgb_code(r, g, b, background)
    end

    # Given red, green and blue values between 0 and 255, this method
    # returns the closest XTerm 256 color value.
    #
    def rgb_256(r, g, b)
      # TODO: what was rgb_valid for?
      #r, g, b = [r, g, b].map{ |c| rgb_valid(c); (6 * (c.to_f / 256.0)).to_i }
      r, g, b = [r, g, b].map{ |c| (6 * (c.to_f / 256.0)).to_i }
      v = (r * 36 + g * 6 + b + 16).abs
      raise ArgumentError, "RGB value is outside 0-255 range -- #{v}" if v > 255
      v
    end

  end

  #
  extend Code
end

