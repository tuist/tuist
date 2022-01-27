module ANSI

  # Table of codes used throughout the system.
  #
  # @see http://en.wikipedia.org/wiki/ANSI_escape_code
  CHART = {
    :clear            => 0,
    :reset            => 0,
    :bright           => 1,
    :bold             => 1,
    :faint            => 2,
    :dark             => 2,
    :italic           => 3,
    :underline        => 4,
    :underscore       => 4,
    :blink            => 5,
    :slow_blink       => 5,
    :rapid            => 6,
    :rapid_blink      => 6,
    :invert           => 7,
    :inverse          => 7,
    :reverse          => 7,
    :negative         => 7,
    :swap             => 7,
    :conceal          => 8,
    :concealed        => 8,
    :hide             => 9,
    :strike           => 9,

    :default_font     => 10,
    :font_default     => 10,
    :font0            => 10,
    :font1            => 11,
    :font2            => 12,
    :font3            => 13,
    :font4            => 14,
    :font5            => 15,
    :font6            => 16,
    :font7            => 17,
    :font8            => 18,
    :font9            => 19,
    :fraktur          => 20,
    :bright_off       => 21,
    :bold_off         => 21,
    :double_underline => 21,
    :clean            => 22,
    :italic_off       => 23,
    :fraktur_off      => 23,
    :underline_off    => 24,
    :blink_off        => 25,
    :inverse_off      => 26,
    :positive         => 26,
    :conceal_off      => 27,
    :show             => 27,
    :reveal           => 27,
    :crossed_off      => 29,
    :crossed_out_off  => 29,

    :black            => 30,
    :red              => 31,
    :green            => 32,
    :yellow           => 33,
    :blue             => 34,
    :magenta          => 35,
    :cyan             => 36,
    :white            => 37,

    :on_black         => 40,
    :on_red           => 41,
    :on_green         => 42,
    :on_yellow        => 43,
    :on_blue          => 44,
    :on_magenta       => 45,
    :on_cyan          => 46,
    :on_white         => 47,

    :frame            => 51,
    :encircle         => 52,
    :overline         => 53,
    :frame_off        => 54,
    :encircle_off     => 54,
    :overline_off     => 55,
  }

  #
  SPECIAL_CHART = {
    :save             => "\e[s",     # Save current cursor positon.
    :restore          => "\e[u",     # Restore saved cursor positon.
    :clear_eol        => "\e[K",     # Clear to the end of the current line.
    :clr              => "\e[K",     # Clear to the end of the current line.
    :clear_right      => "\e[0K",    # Clear to the end of the current line.
    :clear_left       => "\e[1K",    # Clear to the start of the current line.
    :clear_line       => "\e[2K",    # Clear the entire current line.
    :clear_screen     => "\e[2J",    # Clear the screen and move cursor to home.
    :cls              => "\e[2J",    # Clear the screen and move cursor to home.
    :cursor_hide      => "\e[?25l",  # Hide the cursor.
    :cursor_show      => "\e[?25h"   # Show the cursor.
  }

end
