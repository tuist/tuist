# ANSI::Mixin

The ANSI::Mixin module is design for including into
String-like classes. It will support any class that defines
a #to_s method.

    require 'ansi/mixin'

In this demonstration we will simply include it in the
core String class.

    class ::String
      include ANSI::Mixin
    end

Now all strings will have access to ANSI's style and color
codes via simple method calls.

    "roses".red.assert == "\e[31mroses\e[0m"

    "violets".blue.assert == "\e[34mviolets\e[0m"

    "sugar".italic.assert == "\e[3msugar\e[0m"

The method can be combined, of course.

    "you".italic.bold.assert == "\e[1m\e[3myou\e[0m\e[0m"

The mixin also supports background methods.

    "envy".on_green.assert == "\e[42menvy\e[0m"

And it also supports the combined foreground-on-background 
methods.

    "b&w".white_on_black.assert == "\e[37m\e[40mb&w\e[0m"

