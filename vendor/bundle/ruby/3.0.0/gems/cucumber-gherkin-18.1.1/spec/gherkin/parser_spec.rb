require 'rspec'
require 'gherkin'

describe Gherkin::Parser do
  context '.new' do
    it 'can be invoked with no args' do
      Gherkin::Parser.new
    end
  end
end
