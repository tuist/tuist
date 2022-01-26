require 'spec_helper'

RSpec.describe('Anchor scanning') do
  include_examples 'scan', '^abc',    0 => [:anchor,  :bol,              '^',    0, 1]
  include_examples 'scan', 'abc$',    1 => [:anchor,  :eol,              '$',    3, 4]

  include_examples 'scan', '\Aabc',   0 => [:anchor,  :bos,              '\A',   0, 2]
  include_examples 'scan', 'abc\z',   1 => [:anchor,  :eos,              '\z',   3, 5]
  include_examples 'scan', 'abc\Z',   1 => [:anchor,  :eos_ob_eol,       '\Z',   3, 5]

  include_examples 'scan', 'a\bc',    1 => [:anchor,  :word_boundary,    '\b',   1, 3]
  include_examples 'scan', 'a\Bc',    1 => [:anchor,  :nonword_boundary, '\B',   1, 3]

  include_examples 'scan', 'a\Gc',    1 => [:anchor,  :match_start,      '\G',   1, 3]

  include_examples 'scan', "\\\\Ac",  0 => [:escape, :backslash,         '\\\\', 0, 2]
  include_examples 'scan', "a\\\\z",  1 => [:escape, :backslash,         '\\\\', 1, 3]
  include_examples 'scan', "a\\\\Z",  1 => [:escape, :backslash,         '\\\\', 1, 3]
  include_examples 'scan', "a\\\\bc", 1 => [:escape, :backslash,         '\\\\', 1, 3]
  include_examples 'scan', "a\\\\Bc", 1 => [:escape, :backslash,         '\\\\', 1, 3]
end
