require 'spec_helper'

RSpec.describe('Literal lexing') do
  # ascii, single byte characters
  include_examples 'lex', 'a',
    0 => [:literal,     :literal,       'a',        0, 1, 0, 0, 0]

  include_examples 'lex', 'ab+',
    0 => [:literal,     :literal,       'a',        0, 1, 0, 0, 0],
    1 => [:literal,     :literal,       'b',        1, 2, 0, 0, 0],
    2 => [:quantifier,  :one_or_more,   '+',        2, 3, 0, 0, 0]

  # 2 byte wide characters
  include_examples 'lex', 'äöü+',
    0 => [:literal,     :literal,       'äö',       0, 2, 0, 0, 0],
    1 => [:literal,     :literal,       'ü',        2, 3, 0, 0, 0],
    2 => [:quantifier,  :one_or_more,   '+',        3, 4, 0, 0, 0]

  # 3 byte wide characters, Japanese
  include_examples 'lex', 'ab?れます+cd',
    0 => [:literal,     :literal,       'a',        0, 1, 0, 0, 0],
    1 => [:literal,     :literal,       'b',        1, 2, 0, 0, 0],
    2 => [:quantifier,  :zero_or_one,   '?',        2, 3, 0, 0, 0],
    3 => [:literal,     :literal,       'れま',     3, 5, 0, 0, 0],
    4 => [:literal,     :literal,       'す',       5, 6, 0, 0, 0],
    5 => [:quantifier,  :one_or_more,   '+',        6, 7, 0, 0, 0],
    6 => [:literal,     :literal,       'cd',       7, 9, 0, 0, 0]

  # 4 byte wide characters, Osmanya
  include_examples 'lex', '𐒀𐒁?𐒂ab+𐒃',
    0 => [:literal,     :literal,       '𐒀',        0, 1, 0, 0, 0],
    1 => [:literal,     :literal,       '𐒁',        1, 2, 0, 0, 0],
    2 => [:quantifier,  :zero_or_one,   '?',        2, 3, 0, 0, 0],
    3 => [:literal,     :literal,       '𐒂a',       3, 5, 0, 0, 0],
    4 => [:literal,     :literal,       'b',        5, 6, 0, 0, 0],
    5 => [:quantifier,  :one_or_more,   '+',        6, 7, 0, 0, 0],
    6 => [:literal,     :literal,       '𐒃',        7, 8, 0, 0, 0]

  include_examples 'lex', 'mu𝄞?si*𝄫c+',
    0 => [:literal,     :literal,       'mu',       0, 2, 0, 0, 0],
    1 => [:literal,     :literal,       '𝄞',        2, 3, 0, 0, 0],
    2 => [:quantifier,  :zero_or_one,   '?',        3, 4, 0, 0, 0],
    3 => [:literal,     :literal,       's',        4, 5, 0, 0, 0],
    4 => [:literal,     :literal,       'i',        5, 6, 0, 0, 0],
    5 => [:quantifier,  :zero_or_more,  '*',        6, 7, 0, 0, 0],
    6 => [:literal,     :literal,       '𝄫',        7, 8, 0, 0, 0],
    7 => [:literal,     :literal,       'c',        8, 9, 0, 0, 0],
    8 => [:quantifier,  :one_or_more,   '+',        9, 10, 0, 0, 0]

  specify('lex single 2 byte char') do
    tokens = RL.lex("\u0627+")
    expect(tokens.count).to eq 2
  end

  specify('lex single 3 byte char') do
    tokens = RL.lex("\u308C+")
    expect(tokens.count).to eq 2
  end

  specify('lex single 4 byte char') do
    tokens = RL.lex("\u{1D11E}+")
    expect(tokens.count).to eq 2
  end
end
