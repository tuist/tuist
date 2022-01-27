# ANSI::Diff

    require 'ansi/diff'

    a = 'abcYefg'
    b = 'abcXefg'

    diff = ANSI::Diff.new(a,b)

    diff.to_s.assert == "\e[31mabc\e[0m\e[33mYefg\e[0m\n\e[31mabc\e[0mXefg"

Try another.

    a = 'abc'
    b = 'abcdef'

    diff = ANSI::Diff.new(a,b)

    diff.to_s.assert == "\e[31mabc\e[0m\n\e[31mabc\e[0mdef"

And another.

    a = 'abcXXXghi'
    b = 'abcdefghi'

    diff = ANSI::Diff.new(a,b)

    diff.to_s.assert == "\e[31mabc\e[0m\e[33mXXXghi\e[0m\n\e[31mabc\e[0mdefghi"

And another.

    a = 'abcXXXdefghi'
    b = 'abcdefghi'

    diff = ANSI::Diff.new(a,b)

    diff.to_s.assert == "\e[31mabc\e[0m\e[33mXXX\e[0m\e[35mdefghi\e[0m\n\e[31mabc\e[0m\e[35mdefghi\e[0m"

Comparison that is mostly different.

    a = 'abcpppz123'
    b = 'abcxyzzz43'

    diff = ANSI::Diff.new(a,b)

    diff.to_s.assert == "\e[31mabc\e[0m\e[33mpppz123\e[0m\n\e[31mabc\e[0mxyzzz43"

