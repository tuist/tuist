# coding: utf-8
require 'rspec'
require 'gherkin/dialect'

module Gherkin
  describe Dialect do
    it 'provides an interface to the keywords of a dialect' do
      dialect_en = Dialect.for('en')

      expect(dialect_en.feature_keywords).to eq(['Feature', 'Business Need', 'Ability'])
    end
  end
end
