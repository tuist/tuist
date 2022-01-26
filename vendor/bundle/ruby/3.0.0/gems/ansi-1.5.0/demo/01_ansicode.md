# ANSI::Code

Require the library.

    require 'ansi/code'

ANSI::Code can be used as a functions module.

    str = ANSI::Code.red + "Hello" + ANSI::Code.blue + "World"
    str.assert == "\e[31mHello\e[34mWorld"

If a block is supplied to each method then yielded value will
be wrapped in the ANSI code and clear code. 

    str = ANSI::Code.red{ "Hello" } + ANSI::Code.blue{ "World" }
    str.assert == "\e[31mHello\e[0m\e[34mWorld\e[0m"

More conveniently the ANSI::Code module extends ANSI itself.

    str = ANSI.red + "Hello" + ANSI.blue + "World"
    str.assert == "\e[31mHello\e[34mWorld"

    str = ANSI.red{ "Hello" } + ANSI.blue{ "World" }
    str.assert == "\e[31mHello\e[0m\e[34mWorld\e[0m"

ANSI also supports XTerm 256 color mode using red, blue and green values
with the `#rgb` method.

    str = ANSI::Code.rgb(0, 255, 0)
    str.assert == "\e[38;5;46m"

Or using CSS style hex codes as well.

    str = ANSI::Code.rgb("#00FF00")
    str.assert == "\e[38;5;46m"

Both of these methods can take blocks to wrap text in the color and clear codes.

    str = ANSI::Code.rgb("#00FF00"){ "Hello" }
    str.assert == "\e[38;5;46mHello\e[0m"

In the appropriate context the ANSI::Code module can also be
included, making its methods directly accessible.

    include ANSI::Code

    str = red + "Hello" + blue + "World"
    str.assert == "\e[31mHello\e[34mWorld"

    str = red{ "Hello" } + blue{ "World" }
    str.assert == "\e[31mHello\e[0m\e[34mWorld\e[0m"

Along with the single font colors, the library include background colors.

    str = on_red + "Hello"
    str.assert == "\e[41mHello"

As well as combined color methods.

    str = white_on_red + "Hello"
    str.assert == "\e[37m\e[41mHello"

The ANSI::Code module supports most standard ANSI codes, though
not all platforms support every code, so YMMV.

