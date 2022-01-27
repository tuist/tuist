require 'spec_helper'

RSpec.describe('Property scanning') do
  RSpec.shared_examples 'scan property' do |text, token|
    it("scans \\p{#{text}} as property #{token}") do
      result = RS.scan("\\p{#{text}}")[0]
      expect(result[0..1]).to eq [:property, token]
    end

    it("scans \\P{#{text}} as nonproperty #{token}") do
      result = RS.scan("\\P{#{text}}")[0]
      expect(result[0..1]).to eq [:nonproperty, token]
    end

    it("scans \\p{^#{text}} as nonproperty #{token}") do
      result = RS.scan("\\p{^#{text}}")[0]
      expect(result[0..1]).to eq [:nonproperty, token]
    end

    it("scans double-negated \\P{^#{text}} as property #{token}") do
      result = RS.scan("\\P{^#{text}}")[0]
      expect(result[0..1]).to eq [:property, token]
    end
  end

  include_examples 'scan property', 'Alnum',                :alnum

  include_examples 'scan property', 'XPosixPunct',          :xposixpunct

  include_examples 'scan property', 'Newline',              :newline

  include_examples 'scan property', 'Any',                  :any

  include_examples 'scan property', 'Assigned',             :assigned

  include_examples 'scan property', 'Age=1.1',              :'age=1.1'
  include_examples 'scan property', 'Age=10.0',             :'age=10.0'

  include_examples 'scan property', 'ahex',                 :ascii_hex_digit
  include_examples 'scan property', 'ASCII_Hex_Digit',      :ascii_hex_digit # test underscore

  include_examples 'scan property', 'sd',                   :soft_dotted
  include_examples 'scan property', 'Soft-Dotted',          :soft_dotted # test dash

  include_examples 'scan property', 'Egyp',                 :egyptian_hieroglyphs
  include_examples 'scan property', 'Egyptian Hieroglyphs', :egyptian_hieroglyphs # test whitespace

  include_examples 'scan property', 'Linb',                 :linear_b
  include_examples 'scan property', 'Linear-B',             :linear_b # test dash

  include_examples 'scan property', 'InArabic',             :in_arabic # test block
  include_examples 'scan property', 'in Arabic',            :in_arabic # test block w. whitespace
  include_examples 'scan property', 'In_Arabic',            :in_arabic # test block w. underscore

  include_examples 'scan property', 'Yiii',                 :yi
  include_examples 'scan property', 'Yi',                   :yi

  include_examples 'scan property', 'Zinh',                 :inherited
  include_examples 'scan property', 'Inherited',            :inherited
  include_examples 'scan property', 'Qaai',                 :inherited

  include_examples 'scan property', 'Zzzz',                 :unknown
  include_examples 'scan property', 'Unknown',              :unknown
end
