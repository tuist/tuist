require 'spec_helper'

RSpec.describe(Regexp::Expression::Subexpression) do
  specify('#ts, #te') do
    regx = /abcd|ghij|klmn|pqur/
    root = RP.parse(regx)

    alt = root.first

    { 0 => [0, 4], 1 => [5, 9], 2 => [10, 14], 3 => [15, 19] }.each do |index, span|
      sequence = alt[index]

      expect(sequence.ts).to eq span[0]
      expect(sequence.te).to eq span[1]
    end
  end

  specify('#nesting_level') do
    root = RP.parse(/a(b(\d|[ef-g[h]]))/)

    tests = {
      'a'            => 1,
      'b'            => 2,
      '\d|[ef-g[h]]' => 3, # alternation
      '\d'           => 4, # first alternative
      '[ef-g[h]]'    => 4, # second alternative
      'e'            => 5,
      'f-g'          => 5,
      'f'            => 6,
      'g'            => 6,
      'h'            => 6,
    }

    root.each_expression do |exp|
      next unless (expected_nesting_level = tests.delete(exp.to_s))
      expect(expected_nesting_level).to eq exp.nesting_level
    end

    expect(tests).to be_empty
  end

  specify('#dig') do
    root = RP.parse(/(((a)))/)

    expect(root.dig(0).to_s).to eq '(((a)))'
    expect(root.dig(0, 0, 0, 0).to_s).to eq 'a'
    expect(root.dig(0, 0, 0, 0, 0)).to be_nil
    expect(root.dig(3, 7)).to be_nil
  end
end
