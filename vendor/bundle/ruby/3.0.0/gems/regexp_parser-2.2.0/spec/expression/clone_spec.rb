require 'spec_helper'

RSpec.describe('Expression#clone') do
  specify('Base#clone') do
    root = RP.parse(/^(?i:a)b+$/i)
    copy = root.clone

    expect(copy.to_s).to eq root.to_s

    expect(root.object_id).not_to eq copy.object_id
    expect(root.text).to eq copy.text
    expect(root.text.object_id).not_to eq copy.text.object_id

    root_1 = root[1]
    copy_1 = copy[1]

    expect(root_1.options).to eq copy_1.options
    expect(root_1.options.object_id).not_to eq copy_1.options.object_id

    root_2 = root[2]
    copy_2 = copy[2]

    expect(root_2).to be_quantified
    expect(copy_2).to be_quantified
    expect(root_2.quantifier.text).to eq copy_2.quantifier.text
    expect(root_2.quantifier.text.object_id).not_to eq copy_2.quantifier.text.object_id
    expect(root_2.quantifier.object_id).not_to eq copy_2.quantifier.object_id

    # regression test
    expect { root_2.clone }.not_to(change { root_2.quantifier.object_id })
    expect { root_2.clone }.not_to(change { root_2.quantifier.text.object_id })
  end

  specify('Subexpression#clone') do
    root = RP.parse(/^a(b([cde])f)g$/)
    copy = root.clone

    expect(copy.to_s).to eq root.to_s

    expect(root).to respond_to(:expressions)
    expect(copy).to respond_to(:expressions)
    expect(root.expressions.object_id).not_to eq copy.expressions.object_id
    copy.expressions.each_with_index do |exp, index|
      expect(root[index].object_id).not_to eq exp.object_id
    end
    copy[2].each_with_index do |exp, index|
      expect(root[2][index].object_id).not_to eq exp.object_id
    end

    # regression test
    expect { root.clone }.not_to(change { root.expressions.object_id })
  end

  specify('Group::Named#clone') do
    root = RP.parse('^(?<somename>a)+bc$')
    copy = root.clone

    expect(copy.to_s).to eq root.to_s

    root_1 = root[1]
    copy_1 = copy[1]

    expect(root_1.name).to eq copy_1.name
    expect(root_1.name.object_id).not_to eq copy_1.name.object_id
    expect(root_1.text).to eq copy_1.text
    expect(root_1.expressions.object_id).not_to eq copy_1.expressions.object_id
    copy_1.expressions.each_with_index do |exp, index|
      expect(root_1[index].object_id).not_to eq exp.object_id
    end

    # regression test
    expect { root_1.clone }.not_to(change { root_1.name.object_id })
  end

  specify('Group::Options#clone') do
    root = RP.parse('foo(?i)bar')
    copy = root.clone

    expect(copy.to_s).to eq root.to_s

    root_1 = root[1]
    copy_1 = copy[1]

    expect(root_1.option_changes).to eq copy_1.option_changes
    expect(root_1.option_changes.object_id).not_to eq copy_1.option_changes.object_id

    # regression test
    expect { root_1.clone }.not_to(change { root_1.option_changes.object_id })
  end

  specify('Backreference::Base#clone') do
    root = RP.parse('(foo)\1')
    copy = root.clone

    expect(copy.to_s).to eq root.to_s

    root_1 = root[1]
    copy_1 = copy[1]

    expect(root_1.referenced_expression.to_s).to eq copy_1.referenced_expression.to_s
    expect(root_1.referenced_expression.object_id).not_to eq copy_1.referenced_expression.object_id

    # regression test
    expect { root_1.clone }.not_to(change { root_1.referenced_expression.object_id })
  end

  specify('Sequence#clone') do
    root = RP.parse(/(a|b)/)
    copy = root.clone

    # regression test
    expect(copy.to_s).to eq root.to_s

    root_seq_op = root[0][0]
    copy_seq_op = copy[0][0]
    root_seq_1 = root[0][0][0]
    copy_seq_1 = copy[0][0][0]

    expect(root_seq_op.object_id).not_to eq copy_seq_op.object_id
    expect(root_seq_1.object_id).not_to eq copy_seq_1.object_id
    copy_seq_1.expressions.each_with_index do |exp, index|
      expect(root_seq_1[index].object_id).not_to eq exp.object_id
    end
  end

  describe('Base#unquantified_clone') do
    it 'produces a clone' do
      root = RP.parse(/^a(b([cde])f)g$/)
      copy = root.unquantified_clone

      expect(copy.to_s).to eq root.to_s

      expect(copy.object_id).not_to eq root.object_id
    end

    it 'does not carry over the callee quantifier' do
      expect(RP.parse(/a{3}/)[0]).to be_quantified
      expect(RP.parse(/a{3}/)[0].unquantified_clone).not_to be_quantified

      expect(RP.parse(/[a]{3}/)[0]).to be_quantified
      expect(RP.parse(/[a]{3}/)[0].unquantified_clone).not_to be_quantified

      expect(RP.parse(/(a|b){3}/)[0]).to be_quantified
      expect(RP.parse(/(a|b){3}/)[0].unquantified_clone).not_to be_quantified
    end

    it 'keeps quantifiers of callee children' do
      expect(RP.parse(/(a{3}){3}/)[0][0]).to be_quantified
      expect(RP.parse(/(a{3}){3}/)[0].unquantified_clone[0]).to be_quantified
    end
  end
end
