require 'spec_helper'

RSpec.describe('Type scanning') do
  include_examples 'scan', 'a\\dc', 1 => [:type, :digit,     '\\d', 1, 3]
  include_examples 'scan', 'a\\Dc', 1 => [:type, :nondigit,  '\\D', 1, 3]
  include_examples 'scan', 'a\\hc', 1 => [:type, :hex,       '\\h', 1, 3]
  include_examples 'scan', 'a\\Hc', 1 => [:type, :nonhex,    '\\H', 1, 3]
  include_examples 'scan', 'a\\sc', 1 => [:type, :space,     '\\s', 1, 3]
  include_examples 'scan', 'a\\Sc', 1 => [:type, :nonspace,  '\\S', 1, 3]
  include_examples 'scan', 'a\\wc', 1 => [:type, :word,      '\\w', 1, 3]
  include_examples 'scan', 'a\\Wc', 1 => [:type, :nonword,   '\\W', 1, 3]
  include_examples 'scan', 'a\\Rc', 1 => [:type, :linebreak, '\\R', 1, 3]
  include_examples 'scan', 'a\\Xc', 1 => [:type, :xgrapheme, '\\X', 1, 3]
end
