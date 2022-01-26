require 'spec_helper'

RSpec.describe('Expression#to_s') do
  def parse_frozen(pattern, ruby_version = nil)
    IceNine.deep_freeze(RP.parse(pattern, *ruby_version))
  end

  def expect_round_trip(pattern, ruby_version = nil)
    parsed = parse_frozen(pattern, ruby_version)

    expect(parsed.to_s).to eql(pattern)
  end

  specify('literal alternation') do
    expect_round_trip('abcd|ghij|klmn|pqur')
  end

  specify('quantified alternations') do
    expect_round_trip('(?:a?[b]+(c){2}|d+[e]*(f)?)|(?:g+[h]?(i){2,3}|j*[k]{3,5}(l)?)')
  end

  specify('quantified sets') do
    expect_round_trip('[abc]+|[^def]{3,6}')
  end

  specify('property sets') do
    expect_round_trip('[\\a\\b\\p{Lu}\\P{Z}\\c\\d]+', 'ruby/1.9')
  end

  specify('groups') do
    expect_round_trip("(a(?>b(?:c(?<n>d(?'N'e)??f)+g)*+h)*i)++", 'ruby/1.9')
  end

  specify('assertions') do
    expect_round_trip('(a+(?=b+(?!c+(?<=d+(?<!e+)?f+)?g+)?h+)?i+)?', 'ruby/1.9')
  end

  specify('comments') do
    expect_round_trip('(?#start)a(?#middle)b(?#end)')
  end

  specify('options') do
    expect_round_trip('(?mix:start)a(?-mix:middle)b(?i-mx:end)')
  end

  specify('url') do
    expect_round_trip('(^$)|(^(http|https):\\/\\/[a-z0-9]+([\\-\\.]{1}[a-z0-9]+)*' + '\\.[a-z]{2,5}(([0-9]{1,5})?\\/.*)?$)')
  end

  specify('multiline source') do
    multiline = /
          \A
          a?      # One letter
          b{2,5}  # Another one
          [c-g]+  # A set
          \z
        /x

    expect(parse_frozen(multiline).to_s).to eql(multiline.source)
  end

  specify('multiline #to_s') do
    multiline = /
          \A
          a?      # One letter
          b{2,5}  # Another one
          [c-g]+  # A set
          \z
        /x

    expect_round_trip(multiline.to_s)
  end

  # Free spacing expressions that use spaces between quantifiers and their
  # targets do not produce identical results due to the way quantifiers are
  # applied to expressions (members, not nodes) and the merging of consecutive
  # space nodes. This tests that they produce equivalent results.
  specify('multiline equivalence') do
    multiline = /
          \A
          a   ?             # One letter
          b {2,5}           # Another one
          [c-g]  +          # A set
          \z
        /x

    str = 'bbbcged'
    root = parse_frozen(multiline)

    expect(Regexp.new(root.to_s, Regexp::EXTENDED).match(str)[0]).to eql(multiline.match(str)[0])
  end

  # special case: implicit groups used for chained quantifiers produce no parens
  specify 'chained quantifiers #to_s' do
    pattern = /a+{1}{2}/
    root = parse_frozen(pattern)
    expect(root.to_s).to eql('a+{1}{2}')
  end

  # regression test for https://github.com/ammar/regexp_parser/issues/74
  specify('non-ascii comment') do
    pattern = '(?x) 😋 # 😋'
    root = RP.parse(pattern)
    expect(root.last).to be_a(Regexp::Expression::Comment)
    expect(root.last.to_s).to eql('# 😋')
    expect(root.to_s).to eql(pattern)
  end
end
