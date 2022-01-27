# String Extensions

In addition the library offers an extension to String class
called #ansi, which allows some of the ANSI::Code methods
to be called in a more object-oriented fashion.

    require 'ansi/core'

    str = "Hello".ansi(:red) + "World".ansi(:blue)
    str.assert == "\e[31mHello\e[0m\e[34mWorld\e[0m"

