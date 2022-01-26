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


