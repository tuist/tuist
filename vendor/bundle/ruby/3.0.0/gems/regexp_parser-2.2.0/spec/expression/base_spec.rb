require 'spec_helper'

RSpec.describe(Regexp::Expression::Base) do
  specify('#to_re') do
    re_text = '^a*(b([cde]+))+f?$'

    re = RP.parse(re_text).to_re

    expect(re).to be_a(::Regexp)
    expect(re_text).to eq re.source
  end

  specify('#level') do
    regexp = /^a(b(c(d)))e$/
    root = RP.parse(regexp)

    ['^', 'a', '(b(c(d)))', 'e', '$'].each_with_index do |t, i|
      expect(root[i].to_s).to eq t
      expect(root[i].level).to eq 0
    end

    expect(root[2][0].to_s).to eq 'b'
    expect(root[2][0].level).to eq 1

    expect(root[2][1][0].to_s).to eq 'c'
    expect(root[2][1][0].level).to eq 2

    expect(root[2][1][1][0].to_s).to eq 'd'
    expect(root[2][1][1][0].level).to eq 3
  end

  specify('#terminal?') do
    root = RP.parse('^a([b]+)c$')

    expect(root).not_to be_terminal

    expect(root[0]).to be_terminal
    expect(root[1]).to be_terminal
    expect(root[2]).not_to be_terminal
    expect(root[2][0]).not_to be_terminal
    expect(root[2][0][0]).to be_terminal
    expect(root[3]).to be_terminal
    expect(root[4]).to be_terminal
  end

  specify('alt #terminal?') do
    root = RP.parse('^(ab|cd)$')

    expect(root).not_to be_terminal

    expect(root[0]).to be_terminal
    expect(root[1]).not_to be_terminal
    expect(root[1][0]).not_to be_terminal
    expect(root[1][0][0]).not_to be_terminal
    expect(root[1][0][0][0]).to be_terminal
    expect(root[1][0][1]).not_to be_terminal
    expect(root[1][0][1][0]).to be_terminal
  end

  specify('#coded_offset') do
    root = RP.parse('^a*(b+(c?))$')

    expect(root.coded_offset).to eq '@0+12'

    [
      ['@0+1', '^'],
      ['@1+2', 'a*'],
      ['@3+8', '(b+(c?))'],
      ['@11+1', '$'],
    ].each_with_index do |check, i|
      against = [root[i].coded_offset, root[i].to_s]

      expect(against).to eq check
    end

    expect([root[2][0].coded_offset, root[2][0].to_s]).to eq ['@4+2', 'b+']
    expect([root[2][1].coded_offset, root[2][1].to_s]).to eq ['@6+4', '(c?)']
    expect([root[2][1][0].coded_offset, root[2][1][0].to_s]).to eq ['@7+2', 'c?']
  end

  specify('#quantity') do
    expect(RP.parse(/aa/)[0].quantity).to eq [nil, nil]
    expect(RP.parse(/a?/)[0].quantity).to eq [0, 1]
    expect(RP.parse(/a*/)[0].quantity).to eq [0, -1]
    expect(RP.parse(/a+/)[0].quantity).to eq [1, -1]
  end

  specify('#repetitions') do
    expect(RP.parse(/aa/)[0].repetitions).to eq 1..1
    expect(RP.parse(/a?/)[0].repetitions).to eq 0..1
    expect(RP.parse(/a*/)[0].repetitions).to eq 0..(Float::INFINITY)
    expect(RP.parse(/a+/)[0].repetitions).to eq 1..(Float::INFINITY)
  end

  specify('#base_length') do
    expect(RP.parse(/(aa)/)[0].base_length).to eq 4
    expect(RP.parse(/(aa){42}/)[0].base_length).to eq 4
  end

  specify('#full_length') do
    expect(RP.parse(/(aa)/)[0].full_length).to eq 4
    expect(RP.parse(/(aa){42}/)[0].full_length).to eq 8
  end
end
