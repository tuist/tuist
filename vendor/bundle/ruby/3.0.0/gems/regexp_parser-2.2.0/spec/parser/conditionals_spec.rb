require 'spec_helper'

RSpec.describe('Conditional parsing') do
  specify('parse conditional') do
    regexp = /(?<A>a)(?(<A>)T|F)/

    root = RP.parse(regexp, 'ruby/2.0')
    exp = root[1]

    expect(exp).to be_a(Conditional::Expression)

    expect(exp.type).to eq :conditional
    expect(exp.token).to eq :open
    expect(exp.to_s).to eq '(?(<A>)T|F)'
    expect(exp.reference).to eq 'A'
  end

  specify('parse conditional condition') do
    regexp = /(?<A>a)(?(<A>)T|F)/

    root = RP.parse(regexp, 'ruby/2.0')
    exp = root[1].condition

    expect(exp).to be_a(Conditional::Condition)

    expect(exp.type).to eq :conditional
    expect(exp.token).to eq :condition
    expect(exp.to_s).to eq '(<A>)'
    expect(exp.reference).to eq 'A'
    expect(exp.referenced_expression.to_s).to eq '(?<A>a)'
  end

  specify('parse conditional condition with number ref') do
    regexp = /(a)(?(1)T|F)/

    root = RP.parse(regexp, 'ruby/2.0')
    exp = root[1].condition

    expect(exp).to be_a(Conditional::Condition)

    expect(exp.type).to eq :conditional
    expect(exp.token).to eq :condition
    expect(exp.to_s).to eq '(1)'
    expect(exp.reference).to eq 1
    expect(exp.referenced_expression.to_s).to eq '(a)'
  end

  specify('parse conditional nested groups') do
    regexp = /((a)|(b)|((?(2)(c(d|e)+)?|(?(3)f|(?(4)(g|(h)(i)))))))/

    root = RP.parse(regexp, 'ruby/2.0')

    expect(root.to_s).to eq regexp.source

    group = root.first
    expect(group).to be_instance_of(Group::Capture)

    alt = group.first
    expect(alt).to be_instance_of(Alternation)
    expect(alt.length).to eq 3

    expect(alt.map(&:first)).to all(be_a Group::Capture)

    subgroup = alt[2].first
    conditional = subgroup.first

    expect(conditional).to be_instance_of(Conditional::Expression)
    expect(conditional.length).to eq 3

    expect(conditional[0]).to be_instance_of(Conditional::Condition)
    expect(conditional[0].to_s).to eq '(2)'

    condition = conditional.condition
    expect(condition).to be_instance_of(Conditional::Condition)
    expect(condition.to_s).to eq '(2)'

    branches = conditional.branches
    expect(branches.length).to eq 2
    expect(branches).to be_instance_of(Array)
  end

  specify('parse conditional nested') do
    regexp = /(a(b(c(d)(e))))(?(1)(?(2)d|(?(3)e|f))|(?(4)(?(5)g|h)))/

    root = RP.parse(regexp, 'ruby/2.0')

    expect(root.to_s).to eq regexp.source

    {
      1 => [2, root[1]],
      2 => [2, root[1][1][0]],
      3 => [2, root[1][1][0][2][0]],
      4 => [1, root[1][2][0]],
      5 => [2, root[1][2][0][1][0]]
    }.each do |index, example|
      branch_count, exp = example

      expect(exp).to be_instance_of(Conditional::Expression)
      expect(exp.condition.to_s).to eq "(#{index})"
      expect(exp.branches.length).to eq branch_count
    end
  end

  specify('parse conditional nested alternation') do
    regexp = /(a)(?(1)(b|c|d)|(e|f|g))(h)(?(2)(i|j|k)|(l|m|n))|o|p/

    root = RP.parse(regexp, 'ruby/2.0')

    expect(root.to_s).to eq regexp.source

    expect(root.first).to be_instance_of(Alternation)

    [
      [3, 'b|c|d', root[0][0][1][1][0][0]],
      [3, 'e|f|g', root[0][0][1][2][0][0]],
      [3, 'i|j|k', root[0][0][3][1][0][0]],
      [3, 'l|m|n', root[0][0][3][2][0][0]]
    ].each do |example|
      alt_count, alt_text, exp = example

      expect(exp).to be_instance_of(Alternation)
      expect(exp.to_s).to eq alt_text
      expect(exp.alternatives.length).to eq alt_count
    end
  end

  specify('parse conditional extra separator') do
    regexp = /(?<A>a)(?(<A>)T|)/

    root = RP.parse(regexp, 'ruby/2.0')
    branches = root[1].branches

    expect(branches.length).to eq 2

    seq_1, seq_2 = branches

    [seq_1, seq_2].each do |seq|
      expect(seq).to be_a(Sequence)

      expect(seq.type).to eq :expression
      expect(seq.token).to eq :sequence
    end

    expect(seq_1.to_s).to eq 'T'
    expect(seq_2.to_s).to eq ''
  end

  specify('parse conditional quantified') do
    regexp = /(foo)(?(1)\d|(\w)){42}/

    root = RP.parse(regexp, 'ruby/2.0')
    conditional = root[1]

    expect(conditional).to be_quantified
    expect(conditional.quantifier.to_s).to eq '{42}'
    expect(conditional.to_s).to eq '(?(1)\\d|(\\w)){42}'
    expect(conditional.branches.any?(&:quantified?)).to be false
  end

  specify('parse conditional branch content quantified') do
    regexp = /(foo)(?(1)\d{23}|(\w){42})/

    root = RP.parse(regexp, 'ruby/2.0')
    conditional = root[1]

    expect(conditional).not_to be_quantified
    expect(conditional.branches.any?(&:quantified?)).to be false
    expect(conditional.branches[0][0]).to be_quantified
    expect(conditional.branches[0][0].quantifier.to_s).to eq '{23}'
    expect(conditional.branches[1][0]).to be_quantified
    expect(conditional.branches[1][0].quantifier.to_s).to eq '{42}'
  end

  specify('parse conditional excessive branches') do
    regexp = '(?<A>a)(?(<A>)T|F|X)'

    expect { RP.parse(regexp, 'ruby/2.0') }.to raise_error(Conditional::TooManyBranches)
  end
end
