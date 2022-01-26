module ANSI

  module Terminal
    module_function

    #COLS_FALLBACK = 80
    #ROWS_FALLBACK = 25

    #CHARACTER_MODE = "stty"    # For Debugging purposes only.

    #
    # Unix savvy getc().  (second choice)
    #
    # *WARNING*:  This method requires the external "stty" program!
    #
    def get_character(input = STDIN)
      raw_no_echo_mode

      begin
        input.getc
      ensure
        restore_mode
      end
    end

    #
    # Switched the input mode to raw and disables echo.
    #
    # *WARNING*:  This method requires the external "stty" program!
    #
    def raw_no_echo_mode
      @state = `stty -g`
      system "stty raw -echo cbreak isig"
    end

    #
    # Restores a previously saved input mode.
    #
    # *WARNING*:  This method requires the external "stty" program!
    #
    def restore_mode
      system "stty #{@state}"
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

  end

end
