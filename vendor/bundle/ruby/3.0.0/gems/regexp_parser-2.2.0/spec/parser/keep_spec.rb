require 'spec_helper'

RSpec.describe('Keep parsing') do
  include_examples 'parse', /ab\Kcd/, 1      => [:keep, :mark, Keep::Mark, text: '\K']
  include_examples 'parse', /(a\K)/,  [0, 1] => [:keep, :mark, Keep::Mark, text: '\K']
end
