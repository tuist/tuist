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


# String Extensions

In addition the library offers an extension to String class
called #ansi, which allows some of the ANSI::Code methods
to be called in a more object-oriented fashion.

    require 'ansi/core'

    str = "Hello".ansi(:red) + "World".ansi(:blue)
    str.assert == "\e[31mHello\e[0m\e[34mWorld\e[0m"


# ANSI::Logger

Require the ANSI::Logger library.

    require 'ansi/logger'

Create a new ANSI::Logger

    log = ANSI::Logger.new(STDOUT)

Info logging appears normal.

    log.info{"Info logs are green.\n"}

Warn logging appears yellow.

    log.warn{"Warn logs are yellow.\n"}

Debug logging appears cyan.

    log.debug{"Debug logs are cyan.\n"}

Error logging appears red.

    log.error{"Error logs are red.\n"}

Fatal logging appears bright red.

    log.fatal{"Fatal logs are bold red!\n"}


# ANSI::Progressbar

Pretty progress bars are easy to construct.

    require 'ansi/progressbar'

    pbar = ANSI::Progressbar.new("Test Bar", 100)

Running the bar simply requires calling the #inc method during
a loop and calling #finish when done.

    100.times do |i|
      sleep 0.01
      pbar.inc
    end
    pbar.finish

We will use this same rountine in all the examples below, so lets
make a quick macro for it. Notice we have to use #reset first
before reusing the same progress bar.

    def run(pbar)
      pbar.reset
      100.times do |i|
        sleep 0.01
        pbar.inc
      end
      pbar.finish
      puts
    end

The progress bar can be stylized in almost any way.
The #format setter provides control over the parts
that appear on the line. For example, by default the
format is:

    pbar.format("%-14s %3d%% %s %s", :title, :percentage, :bar, :stat)

So lets vary it up to demonstrate the case.

    pbar.format("%-14s %3d%% %s %s", :title, :percentage, :stat, :bar)
    run(pbar)

The progress bar has an extra build in format intended for use with
file downloads called #transer_mode.

    pbar.transfer_mode
    run(pbar)

Calling this methods is the same as calling:

    pbar.format("%-14s %3d%% %s %s",:title, :percentage, :bar, :stat_for_file_transfer)
    run(pbar)

The #style setter allows each part of the line be modified with ANSI codes. And the
#bar_mark writer can be used to change the character used to make the bar.

    pbar.standard_mode
    pbar.style(:title => [:red], :bar=>[:blue])
    pbar.bar_mark = "="
    run(pbar)


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


# ANSI::Columns

The +Columns+ class makes it easy to create nice looking text columns,
sorted from top to bottom, right to left (as opposed to the other way
around).

    require 'ansi/columns'

    list = %w{a b c d e f g h i j k l}

    columns = ANSI::Columns.new(list)

    columns.to_s(4)

The output will be:

    a d g j
    b e h k
    c f i l

Besides an array of elements, Columns.new can take a string in which
the elements are divided by newlines characters. The default column
size can also be given to the initializer.

    list = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl"

    columns = ANSI::Columns.new(list, :columns=>6)

    columns.to_s

The output will be:

    a c e g i k
    b d f h j l

If the column count is +nil+, then the number of columns will be calculated
as a best fit for the current terminal window.

## Padding

Columns can adjust the padding between cells.

    list = %w{a b c d e f g h i j k l}

    columns = ANSI::Columns.new(list, :padding=>2)

    columns.to_s(4)

The output will be:

    a  d  g  j
    b  e  h  k
    c  f  i  l

## Alignment

Columns can also be aligned either left or right.

    list = %w{xx xx xx yy y yy z zz z}

    columns = ANSI::Columns.new(list, :align=>:right)

    columns.to_s(3)

The output will be:

    xx yy  z
    xx  y zz
    xx yy  z

## Format

Lastly, columns can be augmented with ANSI codes. This is done through
a formatting block. The block can take up to three parameters, the cell
content, the column and row numbers, or the cell and the column and row
numbers.

    list = %w{a b c d e f g h i j k l}

    columns = ANSI::Columns.new(list){ |c,r| r % 2 == 0 ? :red : :blue }

    out = columns.to_s(4)

    out.assert == (
      "\e[31ma \e[0m\e[31md \e[0m\e[31mg \e[0m\e[31mj \e[0m\n" +
      "\e[34mb \e[0m\e[34me \e[0m\e[34mh \e[0m\e[34mk \e[0m\n" +
      "\e[31mc \e[0m\e[31mf \e[0m\e[31mi \e[0m\e[31ml \e[0m\n"
    )


# ANSI::Table

The ANSI::Table class can be used to output tabular data with nicely
formated ASCII cell borders.

    require 'ansi/table'

The constructor takes an 2-dimensional array.

    data = [
      [ 10, 20, 30 ],
      [ 20, 10, 20 ],
      [ 50, 40, 20 ]
    ]

    table = ANSI::Table.new(data)

    table.to_s

The output will be:

    +----+----+----+
    | 10 | 20 | 30 |
    | 20 | 10 | 20 |
    | 50 | 40 | 20 |
    +----+----+----+



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


# ANSI::BBCode

The BBCode module provides methods for converting between
BBCodes, basic HTML and ANSI codes.

    require 'ansi/bbcode'

BBCodes are color and style codes in square brackets, quite
popular with on line forums.

    bbcode = "this is [COLOR=red]red[/COLOR], this is [B]bold[/B]"

We can convert this to ANSI code simply enough:

    ansi = ANSI::BBCode.bbcode_to_ansi(bbcode)

    ansi.assert == "this is \e[0;31mred\e[0m, this is \e[1mbold\e[0m\n"

In addition the BBCode module supports conversion to simple HTML.

    html = ANSI::BBCode.bbcode_to_html(bbcode)

    html.assert == "this is <font color=\"red\">red</font>, this is <strong>bold</strong><br />\n"


# ANSI::Terminal

We should be ables to get the terminal width via the `terminal_width` method.

    width = ANSI::Terminal.terminal_width

    Fixnum.assert === width


