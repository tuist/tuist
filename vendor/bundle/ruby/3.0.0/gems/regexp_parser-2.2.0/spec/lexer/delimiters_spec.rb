require 'spec_helper'

RSpec.describe('Literal delimiter lexing') do
  include_examples 'lex', '}',
    0 => [:literal,     :literal,       '}',       0,  1,  0, 0, 0]

  include_examples 'lex', '}}',
    0 => [:literal,     :literal,       '}}',      0,  2,  0, 0, 0]

  include_examples 'lex', '{',
    0 => [:literal,     :literal,       '{',       0,  1,  0, 0, 0]

  include_examples 'lex', '{{',
    0 => [:literal,     :literal,       '{{',      0,  2,  0, 0, 0]

  include_examples 'lex', '{}',
    0 => [:literal,     :literal,       '{}',      0,  2,  0, 0, 0]

  include_examples 'lex', '}{',
    0 => [:literal,     :literal,       '}{',      0,  2,  0, 0, 0]

  include_examples 'lex', '}{+',
    0 => [:literal,     :literal,       '}',       0,  1,  0, 0, 0],
    1 => [:literal,     :literal,       '{',       1,  2,  0, 0, 0],
    2 => [:quantifier,  :one_or_more,   '+',       2,  3,  0, 0, 0]

  include_examples 'lex', '{{var}}',
    0 => [:literal,     :literal,       '{{var}}',  0,  7,  0, 0, 0]

  include_examples 'lex', 'a{b}c',
    0 => [:literal,     :literal,       'a{b}c',    0,  5,  0, 0, 0]

  include_examples 'lex', 'a{1,2',
    0 => [:literal,     :literal,       'a{1,2',    0,  5,  0, 0, 0]

  include_examples 'lex', '({.+})',
    0 => [:group,       :capture,       '(',    0,  1,  0, 0, 0],
    1 => [:literal,     :literal,       '{',    1,  2,  1, 0, 0],
    2 => [:meta,        :dot,           '.',    2,  3,  1, 0, 0],
    3 => [:quantifier,  :one_or_more,   '+',    3,  4,  1, 0, 0],
    4 => [:literal,     :literal,       '}',    4,  5,  1, 0, 0],
    5 => [:group,       :close,         ')',    5,  6,  0, 0, 0]

  include_examples 'lex', ']',
    0 => [:literal,     :literal,       ']',        0,  1,  0, 0, 0]

  include_examples 'lex', ']]',
    0 => [:literal,     :literal,       ']]',       0,  2,  0, 0, 0]

  include_examples 'lex', ']\[',
    0 => [:literal,     :literal,       ']',        0,  1,  0, 0, 0],
    1 => [:escape,      :set_open,      '\[',       1,  3,  0, 0, 0]

  include_examples 'lex', '()',
    0 => [:group,       :capture,       '(',        0,  1,  0, 0, 0],
    1 => [:group,       :close,         ')',        1,  2,  0, 0, 0]

  include_examples 'lex', '{abc:.+}}}[^}]]}',
    0 => [:literal,     :literal,       '{abc:',    0,  5,  0, 0, 0],
    1 => [:meta,        :dot,           '.',        5,  6,  0, 0, 0],
    2 => [:quantifier,  :one_or_more,   '+',        6,  7,  0, 0, 0],
    3 => [:literal,     :literal,       '}}}',      7,  10, 0, 0, 0],
    4 => [:set,         :open,          '[',        10, 11, 0, 0, 0],
    5 => [:set,         :negate,        '^',        11, 12, 0, 1, 0],
    6 => [:literal,     :literal,       '}',        12, 13, 0, 1, 0],
    7 => [:set,         :close,         ']',        13, 14, 0, 0, 0],
    8 => [:literal,     :literal,       ']}',       14, 16, 0, 0, 0]
end
