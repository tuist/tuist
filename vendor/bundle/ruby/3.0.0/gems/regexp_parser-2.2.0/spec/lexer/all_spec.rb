require 'spec_helper'

RSpec.describe(Regexp::Lexer) do
  specify('lexer returns an array') do
    expect(RL.lex('abc')).to be_instance_of(Array)
  end

  specify('lexer returns tokens') do
    tokens = RL.lex('^abc+[^one]{2,3}\\b\\d\\\\C-C$')
    expect(tokens).to all(be_a Regexp::Token)
    expect(tokens.map { |token| token.to_a.length }).to all(eq 8)
  end

  specify('lexer token count') do
    tokens = RL.lex(/^(one|two){2,3}([^d\]efm-qz\,\-]*)(ghi)+$/i)
    expect(tokens.length).to eq 28
  end

  specify('lexer scan alias') do
    expect(RL.scan(/a|b|c/)).to eq RL.lex(/a|b|c/)
  end
end
