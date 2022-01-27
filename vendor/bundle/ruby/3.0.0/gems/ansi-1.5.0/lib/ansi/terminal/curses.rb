module ANSI

  module Terminal
    require 'curses'

    module_function

    #CHARACTER_MODE = "curses"    # For Debugging purposes only.

    #
    # Curses savvy getc().
    #
    def get_character(input = STDIN)
      Curses.getch()
    end

    def terminal_size
      Curses.init_screen
      w, r = Curses.cols, Curses.lines
      Curses.close_screen
      return w, r
    end

  end

end
