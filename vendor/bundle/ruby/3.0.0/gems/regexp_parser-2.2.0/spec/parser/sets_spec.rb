require 'spec_helper'

RSpec.describe('CharacterSet parsing') do
  specify('parse set basic') do
    root = RP.parse('[ab]+')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 2

    expect(exp[0]).to be_instance_of(Literal)
    expect(exp[0].text).to eq 'a'
    expect(exp[1]).to be_instance_of(Literal)
    expect(exp[1].text).to eq 'b'

    expect(exp).to be_quantified
    expect(exp.quantifier.min).to eq 1
    expect(exp.quantifier.max).to eq(-1)
  end

  specify('parse set char type') do
    root = RP.parse('[a\\dc]')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 3

    expect(exp[1]).to be_instance_of(CharacterType::Digit)
    expect(exp[1].text).to eq '\\d'
  end

  specify('parse set escape sequence backspace') do
    root = RP.parse('[a\\bc]')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 3

    expect(exp[1]).to be_instance_of(EscapeSequence::Backspace)
    expect(exp[1].text).to eq '\\b'

    expect(exp).to     match 'a'
    expect(exp).to     match "\b"
    expect(exp).not_to match 'b'
    expect(exp).to     match 'c'
  end

  specify('parse set escape sequence hex') do
    root = RP.parse('[a\\x20c]', :any)
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 3

    expect(exp[1]).to be_instance_of(EscapeSequence::Hex)
    expect(exp[1].text).to eq '\\x20'
  end

  specify('parse set escape sequence codepoint') do
    root = RP.parse('[a\\u0640]')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 2

    expect(exp[1]).to be_instance_of(EscapeSequence::Codepoint)
    expect(exp[1].text).to eq '\\u0640'
  end

  specify('parse set escape sequence codepoint list') do
    root = RP.parse('[a\\u{41 1F60D}]')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 2

    expect(exp[1]).to be_instance_of(EscapeSequence::CodepointList)
    expect(exp[1].text).to eq '\\u{41 1F60D}'
  end

  specify('parse set posix class') do
    root = RP.parse('[[:digit:][:^lower:]]+')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 2

    expect(exp[0]).to be_instance_of(PosixClass)
    expect(exp[0].text).to eq '[:digit:]'
    expect(exp[1]).to be_instance_of(PosixClass)
    expect(exp[1].text).to eq '[:^lower:]'
  end

  specify('parse set nesting') do
    root = RP.parse('[a[b[c]d]e]')

    exp = root[0]
    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 3
    expect(exp[0]).to be_instance_of(Literal)
    expect(exp[2]).to be_instance_of(Literal)

    subset1 = exp[1]
    expect(subset1).to be_instance_of(CharacterSet)
    expect(subset1.count).to eq 3
    expect(subset1[0]).to be_instance_of(Literal)
    expect(subset1[2]).to be_instance_of(Literal)

    subset2 = subset1[1]
    expect(subset2).to be_instance_of(CharacterSet)
    expect(subset2.count).to eq 1
    expect(subset2[0]).to be_instance_of(Literal)
  end

  specify('parse set nesting negative') do
    root = RP.parse('[a[^b[c]]]')
    exp = root[0]

    expect(exp).to be_instance_of(CharacterSet)
    expect(exp.count).to eq 2
    expect(exp[0]).to be_instance_of(Literal)
    expect(exp).not_to be_negative

    subset1 = exp[1]
    expect(subset1).to be_instance_of(CharacterSet)
    expect(subset1.count).to eq 2
    expect(subset1[0]).to be_instance_of(Literal)
    expect(subset1).to be_negative

    subset2 = subset1[1]
    expect(subset2).to be_instance_of(CharacterSet)
    expect(subset2.count).to eq 1
    expect(subset2[0]).to be_instance_of(Literal)
    expect(subset2).not_to be_negative
  end

  specify('parse set nesting #to_s') do
    pattern = '[a[b[^c]]]'
    root = RP.parse(pattern)

    expect(root.to_s).to eq pattern
  end

  specify('parse set literals are not merged') do
    root = RP.parse("[#{('a' * 10)}]")
    exp = root[0]

    expect(exp.count).to eq 10
  end

  specify('parse set whitespace is not merged') do
    root = RP.parse("[#{(' ' * 10)}]")
    exp = root[0]

    expect(exp.count).to eq 10
  end

  specify('parse set whitespace is not merged in x mode') do
    root = RP.parse("(?x)[#{(' ' * 10)}]")
    exp = root[1]

    expect(exp.count).to eq 10
  end

  specify('parse set collating sequence') do
    root = RP.parse('[a[.span-ll.]h]', :any)
    exp = root[0]

    expect(exp[1].to_s).to eq '[.span-ll.]'
  end

  specify('parse set character equivalents') do
    root = RP.parse('[a[=e=]h]', :any)
    exp = root[0]

    expect(exp[1].to_s).to eq '[=e=]'
  end
end
