require 'spec_helper'

RSpec.describe('Literal delimiter scanning') do
  include_examples 'scan', '}',
    0 => [:literal,     :literal,       '}',        0,  1]

  include_examples 'scan', '}}',
    0 => [:literal,     :literal,       '}}',       0,  2]

  include_examples 'scan', '{',
    0 => [:literal,     :literal,       '{',        0,  1]

  include_examples 'scan', '{{',
    0 => [:literal,     :literal,       '{{',       0,  2]

  include_examples 'scan', '{}',
    0 => [:literal,     :literal,       '{}',       0,  2]

  include_examples 'scan', '}{',
    0 => [:literal,     :literal,       '}{',       0,  2]

  include_examples 'scan', '}{+',
    0 => [:literal,     :literal,       '}{',       0,  2]

  include_examples 'scan', '{{var}}',
    0 => [:literal,     :literal,       '{{var}}',  0,  7]

  include_examples 'scan', 'a{1,2',
    0 => [:literal,     :literal,       'a{1,2',    0,  5]

  include_examples 'scan', '({.+})',
    0 => [:group,       :capture,       '(',        0,  1],
    1 => [:literal,     :literal,       '{',        1,  2],
    2 => [:meta,        :dot,           '.',        2,  3],
    3 => [:quantifier,  :one_or_more,   '+',        3,  4],
    4 => [:literal,     :literal,       '}',        4,  5],
    5 => [:group,       :close,         ')',        5,  6]

  include_examples 'scan', ']',
    0 => [:literal,     :literal,       ']',        0,  1]

  include_examples 'scan', ']]',
    0 => [:literal,     :literal,       ']]',       0,  2]

  include_examples 'scan', ']\[',
    0 => [:literal,     :literal,       ']',        0,  1],
    1 => [:escape,      :set_open,      '\[',       1,  3]

  include_examples 'scan', '()',
    0 => [:group,       :capture,       '(',        0,  1],
    1 => [:group,       :close,         ')',        1,  2]
end
