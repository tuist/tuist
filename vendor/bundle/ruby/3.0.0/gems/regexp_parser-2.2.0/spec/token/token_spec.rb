require 'spec_helper'

RSpec.describe(Regexp::Token) do
  specify('#offset') do
    regexp = /ab?cd/
    tokens = RL.lex(regexp)

    expect(tokens[1].text).to eq 'b'
    expect(tokens[1].offset).to eq [1, 2]

    expect(tokens[2].text).to eq '?'
    expect(tokens[2].offset).to eq [2, 3]

    expect(tokens[3].text).to eq 'cd'
    expect(tokens[3].offset).to eq [3, 5]
  end

  specify('#length') do
    regexp = /abc?def/
    tokens = RL.lex(regexp)

    expect(tokens[0].text).to eq 'ab'
    expect(tokens[0].length).to eq 2

    expect(tokens[1].text).to eq 'c'
    expect(tokens[1].length).to eq 1

    expect(tokens[2].text).to eq '?'
    expect(tokens[2].length).to eq 1

    expect(tokens[3].text).to eq 'def'
    expect(tokens[3].length).to eq 3
  end

  specify('#to_h') do
    regexp = /abc?def/
    tokens = RL.lex(regexp)

    expect(tokens[0].text).to eq 'ab'
    expect(tokens[0].to_h).to eq type: :literal, token: :literal, text: 'ab', ts: 0, te: 2, level: 0, set_level: 0, conditional_level: 0

    expect(tokens[2].text).to eq '?'
    expect(tokens[2].to_h).to eq type: :quantifier, token: :zero_or_one, text: '?', ts: 3, te: 4, level: 0, set_level: 0, conditional_level: 0
  end

  specify('#next') do
    regexp = /a+b?c*d{2,3}/
    tokens = RL.lex(regexp)

    a = tokens.first
    expect(a.text).to eq 'a'

    plus = a.next
    expect(plus.text).to eq '+'

    b = plus.next
    expect(b.text).to eq 'b'

    interval = tokens.last
    expect(interval.text).to eq '{2,3}'

    expect(interval.next).to be_nil
  end

  specify('#previous') do
    regexp = /a+b?c*d{2,3}/
    tokens = RL.lex(regexp)

    interval = tokens.last
    expect(interval.text).to eq '{2,3}'

    d = interval.previous
    expect(d.text).to eq 'd'

    star = d.previous
    expect(star.text).to eq '*'

    c = star.previous
    expect(c.text).to eq 'c'

    a = tokens.first
    expect(a.text).to eq 'a'
    expect(a.previous).to be_nil
  end
end
