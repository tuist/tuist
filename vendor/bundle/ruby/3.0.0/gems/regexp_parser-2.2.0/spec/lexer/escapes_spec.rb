require 'spec_helper'

RSpec.describe('Escape lexing') do
  include_examples 'lex', '\u{62}',
    0 => [:escape,  :codepoint_list, '\u{62}',       0, 6,  0, 0, 0]

  include_examples 'lex', '\u{62 63 64}',
    0 => [:escape,  :codepoint_list, '\u{62 63 64}', 0, 12, 0, 0, 0]

  include_examples 'lex', '\u{62 63 64}+',
    0 => [:escape,     :codepoint_list, '\u{62 63}',  0,  9,  0, 0, 0],
    1 => [:escape,     :codepoint_list, '\u{64}',     9,  15, 0, 0, 0],
    2 => [:quantifier, :one_or_more,    '+',          15, 16, 0, 0, 0]
end
