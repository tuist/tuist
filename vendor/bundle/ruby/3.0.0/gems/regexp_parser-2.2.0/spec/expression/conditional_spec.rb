require 'spec_helper'

RSpec.describe(Regexp::Expression::Conditional) do
  let(:root)   { RP.parse('^(a(b))(b(?(1)c|(?(2)d|(?(3)e|f)))g)$') }
  let(:cond_1) { root[2][1] }
  let(:cond_2) { root[2][1][2][0] }
  let(:cond_3) { root[2][1][2][0][2][0] }

  specify('root level') do
    [
      '^',
      '(a(b))',
      '(b(?(1)c|(?(2)d|(?(3)e|f)))g)',
      '$'
    ].each_with_index do |t, i|
      expect(root[i].conditional_level).to eq 0
      expect(root[i].to_s).to eq t
    end

    expect(root[2][0].to_s).to eq 'b'
    expect(root[2][0].conditional_level).to eq 0
  end

  specify('level one') do
    condition = cond_1.condition
    branch_1 = cond_1.branches.first

    expect(condition).to be_a Conditional::Condition
    expect(condition.to_s).to eq '(1)'
    expect(condition.conditional_level).to eq 1

    expect(branch_1).to be_a Conditional::Branch
    expect(branch_1.to_s).to eq 'c'
    expect(branch_1.conditional_level).to eq 1

    expect(branch_1.first.to_s).to eq 'c'
    expect(branch_1.first.conditional_level).to eq 1
  end

  specify('level two') do
    condition = cond_2.condition
    branch_1 = cond_2.branches.first
    branch_2 = cond_2.branches.last

    expect(cond_2.to_s).to start_with '(?'
    expect(cond_2.conditional_level).to eq 1

    expect(condition).to be_a Conditional::Condition
    expect(condition.to_s).to eq '(2)'
    expect(condition.conditional_level).to eq 2

    expect(branch_1).to be_a Conditional::Branch
    expect(branch_1.to_s).to eq 'd'
    expect(branch_1.conditional_level).to eq 2

    expect(branch_1.first.to_s).to eq 'd'
    expect(branch_1.first.conditional_level).to eq 2

    expect(branch_2.first.to_s).to start_with '(?'
    expect(branch_2.first.conditional_level).to eq 2
  end

  specify('level three') do
    condition = cond_3.condition
    branch_1 = cond_3.branches.first
    branch_2 = cond_3.branches.last

    expect(condition).to be_a Conditional::Condition
    expect(condition.to_s).to eq '(3)'
    expect(condition.conditional_level).to eq 3

    expect(cond_3.to_s).to eq '(?(3)e|f)'
    expect(cond_3.conditional_level).to eq 2

    expect(branch_1).to be_a Conditional::Branch
    expect(branch_1.to_s).to eq 'e'
    expect(branch_1.conditional_level).to eq 3

    expect(branch_1.first.to_s).to eq 'e'
    expect(branch_1.first.conditional_level).to eq 3

    expect(branch_2).to be_a Conditional::Branch
    expect(branch_2.to_s).to eq 'f'
    expect(branch_2.conditional_level).to eq 3

    expect(branch_2.first.to_s).to eq 'f'
    expect(branch_2.first.conditional_level).to eq 3
  end
end
