module ANSI

  module Terminal
    # Cygwin will look like Windows, but we want to treat it like a Posix OS:
    raise LoadError, "Cygwin is a Posix OS." if RUBY_PLATFORM =~ /\bcygwin\b/i

    require "Win32API"             # See if we're on Windows.

    module_function

    #CHARACTER_MODE = "Win32API"    # For Debugging purposes only.

    #
    # Windows savvy getc().
    #
    #
    def get_character( input = STDIN )
      @stdin_handle ||= GetStdHandle(STD_INPUT_HANDLE)

      begin
          SetConsoleEcho(@stdin_handle, false)
          input.getc
      ensure
          SetConsoleEcho(@stdin_handle, true)
      end
    end

    # A Windows savvy method to fetch the console columns, and rows.
    def terminal_size
      stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE)

      bufx, bufy, curx, cury, wattr, left, top, right, bottom, maxx, maxy =
        GetConsoleScreenBufferInfo(stdout_handle)
      return right - left + 1, bottom - top + 1
    end

    # windows savvy console echo toggler
    def SetConsoleEcho( console_handle, on )
      mode = GetConsoleMode(console_handle)

      # toggle the console echo bit
      if on
          mode |=  ENABLE_ECHO_INPUT
      else
          mode &= ~ENABLE_ECHO_INPUT
      end

      ok = SetConsoleMode(console_handle, mode)
    end

    # win32 console APIs

    STD_INPUT_HANDLE  = -10
    STD_OUTPUT_HANDLE = -11
    STD_ERROR_HANDLE  = -12

    ENABLE_PROCESSED_INPUT    = 0x0001
    ENABLE_LINE_INPUT         = 0x0002
    ENABLE_WRAP_AT_EOL_OUTPUT = 0x0002
    ENABLE_ECHO_INPUT         = 0x0004
    ENABLE_WINDOW_INPUT       = 0x0008
    ENABLE_MOUSE_INPUT        = 0x0010
    ENABLE_INSERT_MODE        = 0x0020
    ENABLE_QUICK_EDIT_MODE    = 0x0040

    @@apiGetStdHandle               = nil
    @@apiGetConsoleMode             = nil
    @@apiSetConsoleMode             = nil
    @@apiGetConsoleScreenBufferInfo = nil

    def GetStdHandle( handle_type )
      @@apiGetStdHandle ||= Win32API.new( "kernel32", "GetStdHandle",
                                          ['L'], 'L' )

      @@apiGetStdHandle.call( handle_type )
    end

    def GetConsoleMode( console_handle )
      @@apiGetConsoleMode ||= Win32API.new( "kernel32", "GetConsoleMode",
                                            ['L', 'P'], 'I' )

      mode = ' ' * 4
      @@apiGetConsoleMode.call(console_handle, mode)
      mode.unpack('L')[0]
    end

    def SetConsoleMode( console_handle, mode )
      @@apiSetConsoleMode ||= Win32API.new( "kernel32", "SetConsoleMode",
                                            ['L', 'L'], 'I' )

      @@apiSetConsoleMode.call(console_handle, mode) != 0
    end

    def GetConsoleScreenBufferInfo( console_handle )
      @@apiGetConsoleScreenBufferInfo ||=
        Win32API.new( "kernel32", "GetConsoleScreenBufferInfo",
                      ['L', 'P'], 'L' )

      format = 'SSSSSssssSS'
      buf    = ([0] * format.size).pack(format)
      @@apiGetConsoleScreenBufferInfo.call(console_handle, buf)
      buf.unpack(format)
    end

  end

end
