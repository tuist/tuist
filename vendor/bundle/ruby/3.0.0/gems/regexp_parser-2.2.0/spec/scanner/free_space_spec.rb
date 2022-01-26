require 'spec_helper'

RSpec.describe('FreeSpace scanning') do
  describe('scan free space tokens') do
    let(:tokens) { RS.scan(/
      a
      b  ?  c  *
      d  {2,3}
      e + | f +
    /x) }

    0.upto(24).select(&:even?).each do |i|
      it "scans #{i} as free space" do
        expect(tokens[i][0]).to eq :free_space
        expect(tokens[i][1]).to eq :whitespace
      end
    end
    0.upto(24).reject(&:even?).each do |i|
      it "does not scan #{i} as free space" do
        expect(tokens[i][0]).not_to eq :free_space
        expect(tokens[i][1]).not_to eq :whitespace
      end
    end

    it 'sets the correct text' do
      [0, 2, 10, 14].each { |i| expect(tokens[i][2]).to eq "\n      " }
      [4, 6, 8, 12].each { |i| expect(tokens[i][2]).to eq '  ' }
    end
  end

  describe('scan free space comments') do
    include_examples 'scan', /
      a + # A + comment
      b  ?  # B ? comment
      c  {2,3} # C {2,3} comment
      d + | e + # D|E comment
    /x,
      5  => [:free_space, :comment,  "# A + comment\n",      11,  25],
      11 => [:free_space, :comment,  "# B ? comment\n",      37,  51],
      17 => [:free_space, :comment,  "# C {2,3} comment\n",  66,  84],
      29 => [:free_space, :comment,  "# D|E comment\n",     100, 114]

    # single line / no trailing newline (c.f. issue #66)
    include_examples 'scan', /a # b/x,
      0 => [:literal,    :literal,    'a',   0,  1],
      1 => [:free_space, :whitespace, ' ',   1,  2],
      2 => [:free_space, :comment,    "# b", 2,  5]

    # without spaces (c.f. issue #66)
    include_examples 'scan', /a#b/x,
      0 => [:literal,    :literal,  'a',   0,  1],
      1 => [:free_space, :comment,  "#b", 1,  3]
  end

  describe('scan free space inlined') do
    include_examples 'scan', /a b(?x:c d e)f g/,
      0 => [:literal,    :literal,     'a b',   0,  3],
      1 => [:group,      :options,     '(?x:',  3,  7],
      2 => [:literal,    :literal,     'c',     7,  8],
      3 => [:free_space, :whitespace,  ' ',     8,  9],
      4 => [:literal,    :literal,     'd',     9, 10],
      5 => [:free_space, :whitespace,  ' ',    10, 11],
      6 => [:literal,    :literal,     'e',    11, 12],
      7 => [:group,      :close,       ')',    12, 13],
      8 => [:literal,    :literal,     'f g',  13, 16]
  end

  describe('scan free space nested') do
    include_examples 'scan', /a b(?x:c d(?-x:e f)g h)i j/,
      0  => [:literal,     :literal,     'a b',     0,  3],
      1  => [:group,       :options,     '(?x:',    3,  7],
      2  => [:literal,     :literal,     'c',       7,  8],
      3  => [:free_space,  :whitespace,  ' ',       8,  9],
      4  => [:literal,     :literal,     'd',       9, 10],
      5  => [:group,       :options,     '(?-x:',  10, 15],
      6  => [:literal,     :literal,     'e f',    15, 18],
      7  => [:group,       :close,       ')',      18, 19],
      8  => [:literal,     :literal,     'g',      19, 20],
      9  => [:free_space,  :whitespace,  ' ',      20, 21],
      10 => [:literal,     :literal,     'h',      21, 22],
      11 => [:group,       :close,       ')',      22, 23],
      12 => [:literal,     :literal,     'i j',    23, 26]
  end

  describe('scan free space nested groups') do
    include_examples 'scan', /(a (b(?x: (c d) (?-x:(e f) )g) h)i j)/,
      0  => [:group,       :capture,     '(',       0,  1],
      1  => [:literal,     :literal,     'a ',      1,  3],
      2  => [:group,       :capture,     '(',       3,  4],
      3  => [:literal,     :literal,     'b',       4,  5],
      4  => [:group,       :options,     '(?x:',    5,  9],
      5  => [:free_space,  :whitespace,  ' ',       9, 10],
      6  => [:group,       :capture,     '(',      10, 11],
      7  => [:literal,     :literal,     'c',      11, 12],
      8  => [:free_space,  :whitespace,  ' ',      12, 13],
      9  => [:literal,     :literal,     'd',      13, 14],
      10 => [:group,       :close,       ')',      14, 15],
      11 => [:free_space,  :whitespace,  ' ',      15, 16],
      12 => [:group,       :options,     '(?-x:',  16, 21],
      13 => [:group,       :capture,     '(',      21, 22],
      14 => [:literal,     :literal,     'e f',    22, 25],
      15 => [:group,       :close,       ')',      25, 26],
      16 => [:literal,     :literal,     ' ',      26, 27],
      17 => [:group,       :close,       ')',      27, 28],
      18 => [:literal,     :literal,     'g',      28, 29],
      19 => [:group,       :close,       ')',      29, 30],
      20 => [:literal,     :literal,     ' h',     30, 32],
      21 => [:group,       :close,       ')',      32, 33],
      22 => [:literal,     :literal,     'i j',    33, 36],
      23 => [:group,       :close,       ')',      36, 37]
  end

  describe('scan free space switch groups') do
    include_examples 'scan', /(a (b((?x) (c d) ((?-x)(e f) )g) h)i j)/,
      0  => [:group,      :capture,        '(',     0,  1],
      1  => [:literal,    :literal,        'a ',    1,  3],
      2  => [:group,      :capture,        '(',     3,  4],
      3  => [:literal,    :literal,        'b',     4,  5],
      4  => [:group,      :capture,        '(',     5,  6],
      5  => [:group,      :options_switch, '(?x',   6,  9],
      6  => [:group,      :close,           ')',    9,  10],
      7  => [:free_space, :whitespace,      ' ',    10, 11],
      8  => [:group,      :capture,         '(',    11, 12],
      9  => [:literal,    :literal,         'c',    12, 13],
      10 => [:free_space, :whitespace,      ' ',    13, 14],
      11 => [:literal,    :literal,         'd',    14, 15],
      12 => [:group,      :close,           ')',    15, 16],
      13 => [:free_space, :whitespace,      ' ',    16, 17],
      14 => [:group,      :capture,         '(',    17, 18],
      15 => [:group,      :options_switch, '(?-x',  18, 22],
      16 => [:group,      :close,          ')',     22, 23],
      17 => [:group,      :capture,        '(',     23, 24],
      18 => [:literal,    :literal,        'e f',   24, 27],
      19 => [:group,      :close,          ')',     27, 28],
      20 => [:literal,    :literal,        ' ',     28, 29],
      21 => [:group,      :close,          ')',     29, 30],
      22 => [:literal,    :literal,        'g',     30, 31],
      23 => [:group,      :close,          ')',     31, 32],
      24 => [:literal,    :literal,        ' h',    32, 34],
      25 => [:group,      :close,          ')',     34, 35],
      26 => [:literal,    :literal,        'i j',   35, 38],
      27 => [:group,      :close,          ')',     38, 39]
  end

  describe('scanning `#` in regular (non-x mode)') do # c.f. issue 70
    include_examples 'scan', /a#bcd/,
      0 => [:literal, :literal, 'a#bcd', 0, 5]
    include_examples 'scan', /a # bcd/,
      0 => [:literal, :literal, 'a # bcd', 0, 7]

    include_examples 'scan', /a#\d/,
      0 => [:literal, :literal, 'a#', 0, 2],
      1 => [:type,    :digit,   '\d', 2, 4]
    include_examples 'scan', /a # \d/,
      0 => [:literal, :literal, 'a # ', 0, 4],
      1 => [:type,    :digit,   '\d',   4, 6]

    include_examples 'scan', /a#()/,
      0 => [:literal, :literal, 'a#', 0, 2],
      1 => [:group,   :capture, '(',  2, 3]
    include_examples 'scan', /a # ()/,
      0 => [:literal, :literal, 'a # ', 0, 4],
      1 => [:group,   :capture, '(',    4, 5]
  end
end
