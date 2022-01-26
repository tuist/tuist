require 'spec_helper'

RSpec.describe('Keep scanning') do
  include_examples 'scan', /ab\Kcd/,
    1 => [:keep, :mark, '\K', 2,  4]

  include_examples 'scan', /(a\Kb)|(c\\\Kd)ef/,
    2 => [:keep, :mark, '\K', 2,  4],
    9 => [:keep, :mark, '\K', 11, 13]
end
