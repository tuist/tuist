require 'spec_helper'

RSpec.describe('passing options to scan') do
  def expect_type_tokens(tokens, type_tokens)
    expect(tokens.map { |type, token, *| [type, token] }).to eq(type_tokens)
  end

  it 'raises if if scanning from a Regexp and options are passed' do
    expect { RS.scan(/a+/, options: ::Regexp::EXTENDED) }.to raise_error(
      ArgumentError,
      'options cannot be supplied unless scanning a String'
    )
  end

  it 'sets free_spacing based on options if scanning from a String' do
    expect_type_tokens(
      RS.scan('a+#c', options: ::Regexp::MULTILINE | ::Regexp::EXTENDED),
      [
        %i[literal literal],
        %i[quantifier one_or_more],
        %i[free_space comment]
      ]
    )
  end

  it 'does not set free_spacing if scanning from a String and passing no options' do
    expect_type_tokens(
      RS.scan('a+#c'),
      [
        %i[literal literal],
        %i[quantifier one_or_more],
        %i[literal literal]
      ]
    )
  end
end
