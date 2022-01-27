module ANSI
  require 'ansi/code'

  # This module is designed specifically for mixing into
  # String-like classes or extending String-like objects.
  #
  # Generally speaking the String#ansi method is the more
  # elegant approach to modifying a string with codes
  # via a method call. But in some cases this Mixin's design
  # might be preferable. Indeed, it original intent was
  # as a compatability layer for the +colored+ gem.

  module Mixin

    def bold       ; ANSI::Code.bold       { to_s } ; end
    def dark       ; ANSI::Code.dark       { to_s } ; end
    def italic     ; ANSI::Code.italic     { to_s } ; end
    def underline  ; ANSI::Code.underline  { to_s } ; end
    def underscore ; ANSI::Code.underscore { to_s } ; end
    def blink      ; ANSI::Code.blink      { to_s } ; end
    def rapid      ; ANSI::Code.rapid      { to_s } ; end
    def reverse    ; ANSI::Code.reverse    { to_s } ; end
    def negative   ; ANSI::Code.negative   { to_s } ; end
    def concealed  ; ANSI::Code.concealed  { to_s } ; end
    def strike     ; ANSI::Code.strike     { to_s } ; end

    def black      ; ANSI::Code.black      { to_s } ; end
    def red        ; ANSI::Code.red        { to_s } ; end
    def green      ; ANSI::Code.green      { to_s } ; end
    def yellow     ; ANSI::Code.yellow     { to_s } ; end
    def blue       ; ANSI::Code.blue       { to_s } ; end
    def magenta    ; ANSI::Code.magenta    { to_s } ; end
    def cyan       ; ANSI::Code.cyan       { to_s } ; end
    def white      ; ANSI::Code.white      { to_s } ; end

    def on_black   ; ANSI::Code.on_black   { to_s } ; end
    def on_red     ; ANSI::Code.on_red     { to_s } ; end
    def on_green   ; ANSI::Code.on_green   { to_s } ; end
    def on_yellow  ; ANSI::Code.on_yellow  { to_s } ; end
    def on_blue    ; ANSI::Code.on_blue    { to_s } ; end
    def on_magenta ; ANSI::Code.on_magenta { to_s } ; end
    def on_cyan    ; ANSI::Code.on_cyan    { to_s } ; end
    def on_white   ; ANSI::Code.on_white   { to_s } ; end

    def black_on_red      ; ANSI::Code.black_on_red      { to_s } ; end
    def black_on_green    ; ANSI::Code.black_on_green    { to_s } ; end
    def black_on_yellow   ; ANSI::Code.black_on_yellow   { to_s } ; end
    def black_on_blue     ; ANSI::Code.black_on_blue     { to_s } ; end
    def black_on_magenta  ; ANSI::Code.black_on_magenta  { to_s } ; end
    def black_on_cyan     ; ANSI::Code.black_on_cyan     { to_s } ; end
    def black_on_white    ; ANSI::Code.black_on_white    { to_s } ; end

    def red_on_black      ; ANSI::Code.red_on_black      { to_s } ; end
    def red_on_green      ; ANSI::Code.red_on_green      { to_s } ; end
    def red_on_yellow     ; ANSI::Code.red_on_yellow     { to_s } ; end
    def red_on_blue       ; ANSI::Code.red_on_blue       { to_s } ; end
    def red_on_magenta    ; ANSI::Code.red_on_magenta    { to_s } ; end
    def red_on_cyan       ; ANSI::Code.red_on_cyan       { to_s } ; end
    def red_on_white      ; ANSI::Code.red_on_white      { to_s } ; end

    def green_on_black    ; ANSI::Code.green_on_black    { to_s } ; end
    def green_on_red      ; ANSI::Code.green_on_red      { to_s } ; end
    def green_on_yellow   ; ANSI::Code.green_on_yellow   { to_s } ; end
    def green_on_blue     ; ANSI::Code.green_on_blue     { to_s } ; end
    def green_on_magenta  ; ANSI::Code.green_on_magenta  { to_s } ; end
    def green_on_cyan     ; ANSI::Code.green_on_cyan     { to_s } ; end
    def green_on_white    ; ANSI::Code.green_on_white    { to_s } ; end

    def yellow_on_black   ; ANSI::Code.yellow_on_black   { to_s } ; end
    def yellow_on_red     ; ANSI::Code.yellow_on_red     { to_s } ; end
    def yellow_on_green   ; ANSI::Code.yellow_on_green   { to_s } ; end
    def yellow_on_blue    ; ANSI::Code.yellow_on_blue    { to_s } ; end
    def yellow_on_magenta ; ANSI::Code.yellow_on_magenta { to_s } ; end
    def yellow_on_cyan    ; ANSI::Code.yellow_on_cyan    { to_s } ; end
    def yellow_on_white   ; ANSI::Code.yellow_on_white   { to_s } ; end

    def blue_on_black     ; ANSI::Code.blue_on_black     { to_s } ; end
    def blue_on_red       ; ANSI::Code.blue_on_red       { to_s } ; end
    def blue_on_green     ; ANSI::Code.blue_on_green     { to_s } ; end
    def blue_on_yellow    ; ANSI::Code.blue_on_yellow    { to_s } ; end
    def blue_on_magenta   ; ANSI::Code.blue_on_magenta   { to_s } ; end
    def blue_on_cyan      ; ANSI::Code.blue_on_cyan      { to_s } ; end
    def blue_on_white     ; ANSI::Code.blue_on_white     { to_s } ; end

    def magenta_on_black  ; ANSI::Code.magenta_on_black  { to_s } ; end
    def magenta_on_red    ; ANSI::Code.magenta_on_red    { to_s } ; end
    def magenta_on_green  ; ANSI::Code.magenta_on_green  { to_s } ; end
    def magenta_on_yellow ; ANSI::Code.magenta_on_yellow { to_s } ; end
    def magenta_on_blue   ; ANSI::Code.magenta_on_blue   { to_s } ; end
    def magenta_on_cyan   ; ANSI::Code.magenta_on_cyan   { to_s } ; end
    def magenta_on_white  ; ANSI::Code.magenta_on_white  { to_s } ; end

    def cyan_on_black     ; ANSI::Code.cyan_on_black     { to_s } ; end
    def cyan_on_red       ; ANSI::Code.cyan_on_red       { to_s } ; end
    def cyan_on_green     ; ANSI::Code.cyan_on_green     { to_s } ; end
    def cyan_on_yellow    ; ANSI::Code.cyan_on_yellow    { to_s } ; end
    def cyan_on_blue      ; ANSI::Code.cyan_on_blue      { to_s } ; end
    def cyan_on_magenta   ; ANSI::Code.cyan_on_magenta   { to_s } ; end
    def cyan_on_white     ; ANSI::Code.cyan_on_white     { to_s } ; end

    def white_on_black    ; ANSI::Code.white_on_black    { to_s } ; end
    def white_on_red      ; ANSI::Code.white_on_red      { to_s } ; end
    def white_on_green    ; ANSI::Code.white_on_green    { to_s } ; end
    def white_on_yellow   ; ANSI::Code.white_on_yellow   { to_s } ; end
    def white_on_blue     ; ANSI::Code.white_on_blue     { to_s } ; end
    def white_on_magenta  ; ANSI::Code.white_on_magenta  { to_s } ; end
    def white_on_cyan     ; ANSI::Code.white_on_cyan     { to_s } ; end

    # Move cursor to line and column, insert +self.to_s+ and return to
    # original positon.
    def display(line, column=0)
      result = "\e[s"
      result << "\e[#{line.to_i};#{column.to_i}H"
      result << to_s
      result << "\e[u"
      result
    end

  end

end
