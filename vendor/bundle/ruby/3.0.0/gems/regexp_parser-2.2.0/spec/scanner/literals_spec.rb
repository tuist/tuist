require 'spec_helper'

RSpec.describe('UTF8 scanning') do
  # ascii, single byte characters
  include_examples 'scan', 'a',
    0 => [:literal,     :literal,       'a',        0, 1]

  include_examples 'scan', 'ab+',
    0 => [:literal,     :literal,       'ab',       0, 2],
    1 => [:quantifier,  :one_or_more,   '+',        2, 3]

  # 2 byte wide characters
  include_examples 'scan', 'äöü',
    0 => [:literal,     :literal,        'äöü',     0, 3]

  # 3 byte wide characters, Japanese
  include_examples 'scan', 'ab?れます+cd',
    0 => [:literal,     :literal,       'ab',       0, 2],
    1 => [:quantifier,  :zero_or_one,   '?',        2, 3],
    2 => [:literal,     :literal,       'れます',    3, 6],
    3 => [:quantifier,  :one_or_more,   '+',        6, 7],
    4 => [:literal,     :literal,       'cd',       7, 9]

  # 4 byte wide characters, Osmanya
  include_examples 'scan', '𐒀𐒁?𐒂ab+𐒃',
    0 => [:literal,     :literal,       '𐒀𐒁',       0, 2],
    1 => [:quantifier,  :zero_or_one,   '?',        2, 3],
    2 => [:literal,     :literal,       '𐒂ab',      3, 6],
    3 => [:quantifier,  :one_or_more,   '+',        6, 7],
    4 => [:literal,     :literal,       '𐒃',        7, 8]

  include_examples 'scan', 'mu𝄞?si*𝄫c+',
    0 => [:literal,     :literal,       'mu𝄞',       0, 3],
    1 => [:quantifier,  :zero_or_one,   '?',        3, 4],
    2 => [:literal,     :literal,       'si',       4, 6],
    3 => [:quantifier,  :zero_or_more,  '*',        6, 7],
    4 => [:literal,     :literal,       '𝄫c',       7, 9],
    5 => [:quantifier,  :one_or_more,   '+',        9, 10]
end
