require 'spec_helper'

RSpec.describe('Quantifier scanning') do
  include_examples 'scan', 'a?',       1 => [:quantifier,  :zero_or_one,             '?',     1, 2]
  include_examples 'scan', 'a??',      1 => [:quantifier,  :zero_or_one_reluctant,   '??',    1, 3]
  include_examples 'scan', 'a?+',      1 => [:quantifier,  :zero_or_one_possessive,  '?+',    1, 3]

  include_examples 'scan', 'a*',       1 => [:quantifier,  :zero_or_more,            '*',     1, 2]
  include_examples 'scan', 'a*?',      1 => [:quantifier,  :zero_or_more_reluctant,  '*?',    1, 3]
  include_examples 'scan', 'a*+',      1 => [:quantifier,  :zero_or_more_possessive, '*+',    1, 3]

  include_examples 'scan', 'a+',       1 => [:quantifier,  :one_or_more,             '+',     1, 2]
  include_examples 'scan', 'a+?',      1 => [:quantifier,  :one_or_more_reluctant,   '+?',    1, 3]
  include_examples 'scan', 'a++',      1 => [:quantifier,  :one_or_more_possessive,  '++',    1, 3]

  include_examples 'scan', 'a{2}',     1 => [:quantifier,  :interval,                '{2}',   1, 4]
  include_examples 'scan', 'a{2,}',    1 => [:quantifier,  :interval,                '{2,}',  1, 5]
  include_examples 'scan', 'a{,2}',    1 => [:quantifier,  :interval,                '{,2}',  1, 5]
  include_examples 'scan', 'a{2,4}',   1 => [:quantifier,  :interval,                '{2,4}', 1, 6]

  # special case: chained quantifiers
  include_examples 'scan', 'a+{2}{3}', 1 => [:quantifier,  :one_or_more,             '+',     1, 2]
  include_examples 'scan', 'a+{2}{3}', 2 => [:quantifier,  :interval,                '{2}',   2, 5]
  include_examples 'scan', 'a+{2}{3}', 3 => [:quantifier,  :interval,                '{3}',   5, 8]
end
