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

