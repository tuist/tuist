# ANSI::String

The ANSI::String class is a very sophisticated implementation
of Ruby's standard String class, but one that can handle
ANSI codes seamlessly.

    require 'ansi/string'

    flower1 = ANSI::String.new("Roses")
    flower2 = ANSI::String.new("Violets")

Like any other string.

    flower1.to_s.assert == "Roses"
    flower2.to_s.assert == "Violets"

Bet now we can add color.

    flower1.red!
    flower2.blue!

    flower1.to_s.assert == "\e[31mRoses\e[0m"
    flower2.to_s.assert == "\e[34mViolets\e[0m"

Despite that the string representation now contains ANSI codes,
we can still manipulate the string in much the same way that
we manipulate an ordinary string.

    flower1.size.assert == 5
    flower2.size.assert == 7

Like ordinary strings we can concatenate the two strings

    flowers = flower1 + ' ' + flower2
    flowers.to_s.assert == "\e[31mRoses\e[0m \e[34mViolets\e[0m"

    flowers.size.assert == 13

Standard case conversion such as #upcase and #downcase work.

    flower1.upcase.to_s.assert == "\e[31mROSES\e[0m"
    flower1.downcase.to_s.assert == "\e[31mroses\e[0m"

Some of the most difficult methods to re-implement were the 
substitution methods such as #sub and #gsub. They are still
somewhat more limited than the original string methods, but
their primary functionality should work.

    flower1.gsub('s', 'z').to_s.assert == "\e[31mRozez\e[0m"

There are still a number of methods that need implementation.
ANSI::String is currently a very partial implementation. But
as you can see from the methods it does currently support,
is it already useful.


