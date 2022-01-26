require 'spec_helper'

RSpec.describe('Keep lexing') do
  include_examples 'lex', /ab\Kcd/,
    1 => [:keep, :mark, '\K', 2,  4,  0, 0, 0]

  include_examples 'lex', /(a\Kb)|(c\\\Kd)ef/,
    2 => [:keep, :mark, '\K', 2,  4,  1, 0, 0],
    9 => [:keep, :mark, '\K', 11, 13, 1, 0, 0]
end
