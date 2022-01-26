require 'spec_helper'

RSpec.describe('FreeSpace parsing') do
  specify('parse free space spaces') do
    regexp = /a ? b * c + d{2,4}/x
    root = RP.parse(regexp)

    0.upto(6) do |i|
      if i.odd?
        expect(root[i]).to be_instance_of(WhiteSpace)
        expect(root[i].text).to eq '  '
      else
        expect(root[i]).to be_instance_of(Literal)
        expect(root[i]).to be_quantified
      end
    end
  end

  specify('parse non free space literals') do
    regexp = /a b c d/
    root = RP.parse(regexp)

    expect(root.first).to be_instance_of(Literal)
    expect(root.first.text).to eq 'a b c d'
  end

  specify('parse free space comments') do
    regexp = /
      a   ?     # One letter
      b {2,5}   # Another one
      [c-g]  +  # A set
      (h|i|j) | # A group
      klm *
      nop +
    /x

    root = RP.parse(regexp)

    alt = root.first
    expect(alt).to be_instance_of(Alternation)

    alt_1 = alt.alternatives.first
    expect(alt_1).to be_instance_of(Alternative)
    expect(alt_1.length).to eq 15

    [0, 2, 4, 6, 8, 12, 14].each do |i|
      expect(alt_1[i]).to be_instance_of(WhiteSpace)
    end

    [3, 7, 11].each { |i| expect(alt_1[i].class).to eq Comment }

    alt_2 = alt.alternatives.last
    expect(alt_2).to be_instance_of(Alternative)
    expect(alt_2.length).to eq 7

    [0, 2, 4, 6].each { |i| expect(alt_2[i].class).to eq WhiteSpace }

    expect(alt_2[1]).to be_instance_of(Comment)
  end

  specify('parse free space nested comments') do
    regexp = /
      # Group one
      (
       abc  # Comment one
       \d?  # Optional \d
      )+

      # Group two
      (
       def  # Comment two
       \s?  # Optional \s
      )?
    /x

    root = RP.parse(regexp)

    top_comment_1 = root[1]
    expect(top_comment_1).to be_instance_of(Comment)
    expect(top_comment_1.text).to eq "# Group one\n"
    expect(top_comment_1.starts_at).to eq 7

    top_comment_2 = root[5]
    expect(top_comment_2).to be_instance_of(Comment)
    expect(top_comment_2.text).to eq "# Group two\n"
    expect(top_comment_2.starts_at).to eq 95

    [3, 7].each do |g,|
      group = root[g]

      [3, 7].each do |c|
        comment = group[c]
        expect(comment).to be_instance_of(Comment)
        expect(comment.text.length).to eq 14
      end
    end
  end

  specify('parse free space quantifiers') do
    regexp = /
      a
      # comment 1
      ?
      (
       b # comment 2
       # comment 3
       +
      )
      # comment 4
      *
    /x

    root = RP.parse(regexp)

    literal_1 = root[1]
    expect(literal_1).to be_instance_of(Literal)
    expect(literal_1).to be_quantified
    expect(literal_1.quantifier.token).to eq :zero_or_one

    group = root[5]
    expect(group).to be_instance_of(Group::Capture)
    expect(group).to be_quantified
    expect(group.quantifier.token).to eq :zero_or_more

    literal_2 = group[1]
    expect(literal_2).to be_instance_of(Literal)
    expect(literal_2).to be_quantified
    expect(literal_2.quantifier.token).to eq :one_or_more
  end
end
