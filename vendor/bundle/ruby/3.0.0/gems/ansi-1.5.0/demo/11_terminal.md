# ANSI::Terminal

We should be ables to get the terminal width via the `terminal_width` method.

    width = ANSI::Terminal.terminal_width

    Fixnum.assert === width

