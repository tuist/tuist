require 'spec_helper'

RSpec.describe('Expression#match') do
  it 'returns the #match result of the respective Regexp' do
    expect(RP.parse(/a/).match('a')[0]).to eq 'a'
  end

  it 'can be given an offset, just like Regexp#match' do
    expect(RP.parse(/./).match('ab', 1)[0]).to eq 'b'
  end

  it 'works with the #=~ alias' do
    expect(RP.parse(/a/) =~ 'a').to be_a MatchData
  end
end

RSpec.describe('Expression#match?') do
  it 'returns true if the Respective Regexp matches' do
    expect(RP.parse(/a/).match?('a')).to be true
  end

  it 'returns false if the Respective Regexp does not match' do
    expect(RP.parse(/a/).match?('b')).to be false
  end
end
