require 'spec_helper'

RSpec.describe('Meta scanning') do
  include_examples 'scan', /abc??|def*+|ghi+/,
    0  => [:literal,     :literal,                 'abc',  0,  3],
    1  => [:quantifier,  :zero_or_one_reluctant,   '??',   3,  5],
    2  => [:meta,        :alternation,             '|',    5,  6],
    3  => [:literal,     :literal,                 'def',  6,  9],
    4  => [:quantifier,  :zero_or_more_possessive, '*+',   9,  11],
    5  => [:meta,        :alternation,             '|',    11, 12]

  include_examples 'scan', /(a\|b)|(c|d)\|(e[|]f)/,
    2  => [:escape,      :alternation,             '\|',   2,  4],
    5  => [:meta,        :alternation,             '|',    6,  7],
    8  => [:meta,        :alternation,             '|',    9,  10],
    11 => [:escape,      :alternation,             '\|',   12, 14],
    15 => [:literal,     :literal,                 '|',    17, 18]
end
