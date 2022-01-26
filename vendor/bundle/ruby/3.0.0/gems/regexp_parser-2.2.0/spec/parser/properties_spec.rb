require 'spec_helper'

RSpec.describe('Property parsing') do
  example_props = [
    'Alnum',
    'Any',
    'Age=1.1',
    'Dash',
    'di',
    'Default_Ignorable_Code_Point',
    'Math',
    'Noncharacter-Code_Point', # test dash
    'sd',
    'Soft Dotted', # test whitespace
    'sterm',
    'xidc',
    'XID_Continue',
    'Emoji',
    'InChessSymbols'
  ]

  example_props.each do |name|
    it("parses property #{name}") do
      exp = RP.parse("ab\\p{#{name}}", '*').last

      expect(exp).to be_a(UnicodeProperty::Base)
      expect(exp.type).to eq :property
      expect(exp.name).to eq name
    end

    it("parses nonproperty #{name}") do
      exp = RP.parse("ab\\P{#{name}}", '*').last

      expect(exp).to be_a(UnicodeProperty::Base)
      expect(exp.type).to eq :nonproperty
      expect(exp.name).to eq name
    end
  end

  if ruby_version_at_least('2.7.0')
    specify('parse all properties of current ruby') do
      unsupported = RegexpPropertyValues.all_for_current_ruby.reject do |prop|
        RP.parse("\\p{#{prop}}") rescue false
      end
      expect(unsupported).to be_empty
    end
  end

  specify('parse property negative') do
    root = RP.parse('ab\p{L}cd', 'ruby/1.9')
    expect(root[1]).not_to be_negative
  end

  specify('parse nonproperty negative') do
    root = RP.parse('ab\P{L}cd', 'ruby/1.9')
    expect(root[1]).to be_negative
  end

  specify('parse caret nonproperty negative') do
    root = RP.parse('ab\p{^L}cd', 'ruby/1.9')
    expect(root[1]).to be_negative
  end

  specify('parse double negated property negative') do
    root = RP.parse('ab\P{^L}cd', 'ruby/1.9')
    expect(root[1]).not_to be_negative
  end

  specify('parse property shortcut') do
    expect(RP.parse('\p{lowercase_letter}')[0].shortcut).to eq 'll'
    expect(RP.parse('\p{sc}')[0].shortcut).to eq 'sc'
    expect(RP.parse('\p{in_bengali}')[0].shortcut).to be_nil
  end

  specify('parse property age') do
    root = RP.parse('ab\p{age=5.2}cd', 'ruby/1.9')
    expect(root[1]).to be_a(UnicodeProperty::Age)
  end

  specify('parse property derived') do
    root = RP.parse('ab\p{Math}cd', 'ruby/1.9')
    expect(root[1]).to be_a(UnicodeProperty::Derived)
  end

  specify('parse property script') do
    root = RP.parse('ab\p{Hiragana}cd', 'ruby/1.9')
    expect(root[1]).to be_a(UnicodeProperty::Script)
  end

  specify('parse property script V1 9 3') do
    root = RP.parse('ab\p{Brahmi}cd', 'ruby/1.9.3')
    expect(root[1]).to be_a(UnicodeProperty::Script)
  end

  specify('parse property script V2 2 0') do
    root = RP.parse('ab\p{Caucasian_Albanian}cd', 'ruby/2.2')
    expect(root[1]).to be_a(UnicodeProperty::Script)
  end

  specify('parse property block') do
    root = RP.parse('ab\p{InArmenian}cd', 'ruby/1.9')
    expect(root[1]).to be_a(UnicodeProperty::Block)
  end

  specify('parse property following literal') do
    root = RP.parse('ab\p{Lu}cd', 'ruby/1.9')
    expect(root[2]).to be_a(Literal)
  end

  specify('parse abandoned newline property') do
    root = RP.parse('\p{newline}', 'ruby/1.9')
    expect(root.expressions.last).to be_a(UnicodeProperty::Base)

    expect { RP.parse('\p{newline}', 'ruby/2.0') }
      .to raise_error(Regexp::Syntax::NotImplementedError)
  end
end
