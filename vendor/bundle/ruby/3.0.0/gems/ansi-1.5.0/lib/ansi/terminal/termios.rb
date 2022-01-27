module ANSI

  module Terminal
    require "termios"             # Unix, first choice.

    module_function

    #CHARACTER_MODE = "termios"    # For Debugging purposes only.

    #
    # Unix savvy getc().  (First choice.)
    #
    # *WARNING*:  This method requires the "termios" library!
    #
    def get_character( input = STDIN )
      old_settings = Termios.getattr(input)

      new_settings                     =  old_settings.dup
      new_settings.c_lflag             &= ~(Termios::ECHO | Termios::ICANON)
      new_settings.c_cc[Termios::VMIN] =  1

      begin
        Termios.setattr(input, Termios::TCSANOW, new_settings)
        input.getc
      ensure
        Termios.setattr(input, Termios::TCSANOW, old_settings)
      end
    end

    # A Unix savvy method to fetch the console columns, and rows.
    def terminal_size
      if /solaris/ =~ RUBY_PLATFORM && (`stty` =~ /\brows = (\d+).*\bcolumns = (\d+)/)
        w, r = [$2, $1]
      else
        w, r = `stty size`.split.reverse
      end
      w = `tput cols` unless w  # last ditch effort to at least get width

      w = w.to_i if w
      r = r.to_i if r

      return w, r
    end

    # Console screen width (taken from progress bar)
    #
    # NOTE: Don't know how portable #screen_width is.
    # TODO: How to fit into system?
    #
    def screen_width(out=STDERR)
      default_width = ENV['COLUMNS'] || 76
      begin
        tiocgwinsz = 0x5413
        data = [0, 0, 0, 0].pack("SSSS")
        if out.ioctl(tiocgwinsz, data) >= 0 then
          rows, cols, xpixels, ypixels = data.unpack("SSSS")
          if cols >= 0 then cols else default_width end
        else
          default_width
        end
      rescue Exception
        default_width
      end
    end

  end

end
