require 'spec_helper'

RSpec.describe('Alternation parsing') do
  let(:root) { RP.parse('(ab??|cd*|ef+)*|(gh|ij|kl)?') }

  specify('parse alternation root') do
    e = root[0]
    expect(e).to be_a(Alternation)
  end

  specify('parse alternation alts') do
    alts = root[0].alternatives

    expect(alts[0]).to be_a(Alternative)
    expect(alts[1]).to be_a(Alternative)

    expect(alts[0][0]).to be_a(Group::Capture)
    expect(alts[1][0]).to be_a(Group::Capture)

    expect(alts.length).to eq 2
  end

  specify('parse alternation nested') do
    e = root[0].alternatives[0][0][0]

    expect(e).to be_a(Alternation)
  end

  specify('parse alternation nested sequence') do
    alts = root[0][0]
    nested = alts[0][0][0]

    expect(nested).to be_a(Alternative)

    expect(nested[0]).to be_a(Literal)
    expect(nested[1]).to be_a(Literal)
    expect(nested.expressions.length).to eq 2
  end

  specify('parse alternation nested groups') do
    root = RP.parse('(i|ey|([ougfd]+)|(ney))')

    alts = root[0][0].alternatives
    expect(alts.length).to eq 4
  end

  specify('parse alternation grouped alts') do
    root = RP.parse('ca((n)|(t)|(ll)|(b))')

    alts = root[1][0].alternatives

    expect(alts.length).to eq 4

    expect(alts[0]).to be_a(Alternative)
    expect(alts[1]).to be_a(Alternative)
    expect(alts[2]).to be_a(Alternative)
    expect(alts[3]).to be_a(Alternative)
  end

  specify('parse alternation nested grouped alts') do
    root = RP.parse('ca((n|t)|(ll|b))')

    alts = root[1][0].alternatives

    expect(alts.length).to eq 2

    expect(alts[0]).to be_a(Alternative)
    expect(alts[1]).to be_a(Alternative)

    subalts = root[1][0][0][0][0].alternatives

    expect(alts.length).to eq 2

    expect(subalts[0]).to be_a(Alternative)
    expect(subalts[1]).to be_a(Alternative)
  end

  specify('parse alternation continues after nesting') do
    root = RP.parse(/a|(b)c/)

    seq = root[0][1].expressions

    expect(seq.length).to eq 2

    expect(seq[0]).to be_a(Group::Capture)
    expect(seq[1]).to be_a(Literal)
  end
end
