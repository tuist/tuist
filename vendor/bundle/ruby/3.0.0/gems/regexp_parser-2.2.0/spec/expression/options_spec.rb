require 'spec_helper'

RSpec.describe('Expression#options') do
  it 'returns a hash of options/flags that affect the expression' do
    exp = RP.parse(/a/ix)[0]
    expect(exp).to be_a Literal
    expect(exp.options).to eq(i: true, x: true)
  end

  it 'includes options that are locally enabled via special groups' do
    exp = RP.parse(/(?x)(?m:a)/i)[1][0]
    expect(exp).to be_a Literal
    expect(exp.options).to eq(i: true, m: true, x: true)
  end

  it 'excludes locally disabled options' do
    exp = RP.parse(/(?x)(?-im:a)/i)[1][0]
    expect(exp).to be_a Literal
    expect(exp.options).to eq(x: true)
  end

  it 'gives correct precedence to negative options' do
    # Negative options have precedence. E.g. /(?i-i)a/ is case-sensitive.
    regexp = /(?i-i:a)/
    expect(regexp).to match 'a'
    expect(regexp).not_to match 'A'

    exp = RP.parse(regexp)[0][0]
    expect(exp).to be_a Literal
    expect(exp.options).to eq({})
  end

  it 'correctly handles multiple negative option parts' do
    regexp = /(?--m--mx--) . /mx
    expect(regexp).to match ' . '
    expect(regexp).not_to match '.'
    expect(regexp).not_to match "\n"

    exp = RP.parse(regexp)[2]
    expect(exp.options).to eq({})
  end

  it 'gives correct precedence when encountering multiple encoding flags' do
    # Any encoding flag overrides all previous encoding flags. If there are
    # multiple encoding flags in an options string, the last one wins.
    # E.g. /(?dau)\w/ matches UTF8 chars but /(?dua)\w/ only ASCII chars.
    regexp1 = /(?dau)\w/
    regexp2 = /(?dua)\w/
    expect(regexp1).to match 'ü'
    expect(regexp2).not_to match 'ü'

    exp1 = RP.parse(regexp1)[1]
    exp2 = RP.parse(regexp2)[1]
    expect(exp1.options).to eq(u: true)
    expect(exp2.options).to eq(a: true)
  end

  it 'is accessible via shortcuts' do
    exp = Root.build

    expect { exp.options[:i] = true }
      .to  change { exp.i? }.from(false).to(true)
      .and change { exp.ignore_case? }.from(false).to(true)
      .and change { exp.case_insensitive? }.from(false).to(true)

    expect { exp.options[:m] = true }
      .to  change { exp.m? }.from(false).to(true)
      .and change { exp.multiline? }.from(false).to(true)

    expect { exp.options[:x] = true }
      .to  change { exp.x? }.from(false).to(true)
      .and change { exp.extended? }.from(false).to(true)
      .and change { exp.free_spacing? }.from(false).to(true)

    expect { exp.options[:a] = true }
      .to  change { exp.a? }.from(false).to(true)
      .and change { exp.ascii_classes? }.from(false).to(true)

    expect { exp.options[:d] = true }
      .to  change { exp.d? }.from(false).to(true)
      .and change { exp.default_classes? }.from(false).to(true)

    expect { exp.options[:u] = true }
      .to  change { exp.u? }.from(false).to(true)
      .and change { exp.unicode_classes? }.from(false).to(true)
  end

  RSpec.shared_examples '#options' do |regexp, path, klass|
    it "works for expression class #{klass}" do
      exp = RP.parse(/#{regexp.source}/i).dig(*path)
      expect(exp).to be_a(klass)
      expect(exp).to be_i
      expect(exp).not_to be_x
    end
  end

  include_examples '#options', //, [], Root
  include_examples '#options', /a/, [0], Literal
  include_examples '#options', /\A/, [0], Anchor::Base
  include_examples '#options', /\d/, [0], CharacterType::Base
  include_examples '#options', /\n/, [0], EscapeSequence::Base
  include_examples '#options', /\K/, [0], Keep::Mark
  include_examples '#options', /./, [0], CharacterType::Any
  include_examples '#options', /(a)/, [0], Group::Base
  include_examples '#options', /(a)/, [0, 0], Literal
  include_examples '#options', /(?=a)/, [0], Assertion::Base
  include_examples '#options', /(?=a)/, [0, 0], Literal
  include_examples '#options', /(a|b)/, [0], Group::Base
  include_examples '#options', /(a|b)/, [0, 0], Alternation
  include_examples '#options', /(a|b)/, [0, 0, 0], Alternative
  include_examples '#options', /(a|b)/, [0, 0, 0, 0], Literal
  include_examples '#options', /(a)\1/, [1], Backreference::Base
  include_examples '#options', /(a)\k<1>/, [1], Backreference::Number
  include_examples '#options', /(a)\g<1>/, [1], Backreference::NumberCall
  include_examples '#options', /[a]/, [0], CharacterSet
  include_examples '#options', /[a]/, [0, 0], Literal
  include_examples '#options', /[a-z]/, [0, 0], CharacterSet::Range
  include_examples '#options', /[a-z]/, [0, 0, 0], Literal
  include_examples '#options', /[a&&z]/, [0, 0], CharacterSet::Intersection
  include_examples '#options', /[a&&z]/, [0, 0, 0], CharacterSet::IntersectedSequence
  include_examples '#options', /[a&&z]/, [0, 0, 0, 0], Literal
  include_examples '#options', /[[:ascii:]]/, [0, 0], PosixClass
  include_examples '#options', /\p{word}/, [0], UnicodeProperty::Base
  include_examples '#options', /(a)(?(1)b|c)/, [1], Conditional::Expression
  include_examples '#options', /(a)(?(1)b|c)/, [1, 0], Conditional::Condition
  include_examples '#options', /(a)(?(1)b|c)/, [1, 1], Conditional::Branch
  include_examples '#options', /(a)(?(1)b|c)/, [1, 1, 0], Literal
end
