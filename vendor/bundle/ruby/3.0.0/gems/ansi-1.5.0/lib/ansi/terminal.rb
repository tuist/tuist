module ANSI

  # = Terminal
  #
  # This library is based of HighLine's SystemExtensions
  # by James Edward Gray II.
  #
  # Copyright 2006 Gray Productions
  #
  # Distributed under the tems of the
  # {Ruby software license}[http://www.ruby-lang.org/en/LICENSE.txt].

  module Terminal

    module_function

    modes = %w{win32 termios curses stty}

    # This section builds character reading and terminal size functions
    # to suit the proper platform we're running on.
    #
    # Be warned: Here be dragons!
    #
    begin
      require 'ansi/terminal/' + (mode = modes.shift)
      CHARACTER_MODE = mode
    rescue LoadError
      retry
    end

    # Get the width of the terminal window.
    def terminal_width
      terminal_size.first
    end

    # Get the height of the terminal window.
    def terminal_height
      terminal_size.last
    end

  end

end

