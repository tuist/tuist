require 'spec_helper'

ML = Regexp::MatchLength

RSpec.describe(Regexp::MatchLength) do
  specify('literal') { expect(ML.of(/a/).minmax).to eq [1, 1] }
  specify('literal sequence') { expect(ML.of(/abc/).minmax).to eq [3, 3] }
  specify('dot') { expect(ML.of(/./).minmax).to eq [1, 1] }
  specify('set') { expect(ML.of(/[abc]/).minmax).to eq [1, 1] }
  specify('type') { expect(ML.of(/\d/).minmax).to eq [1, 1] }
  specify('escape') { expect(ML.of(/\n/).minmax).to eq [1, 1] }
  specify('property') { expect(ML.of(/\p{ascii}/).minmax).to eq [1, 1] }
  specify('codepoint list') { expect(ML.of(/\u{61 62 63}/).minmax).to eq [3, 3] }
  specify('multi-char literal') { expect(ML.of(/abc/).minmax).to eq [3, 3] }
  specify('fixed quantified') { expect(ML.of(/a{5}/).minmax).to eq [5, 5] }
  specify('range quantified') { expect(ML.of(/a{5,9}/).minmax).to eq [5, 9] }
  specify('nested quantified') { expect(ML.of(/(a{2}){3,4}/).minmax).to eq [6, 8] }
  specify('open-end quantified') { expect(ML.of(/a*/).minmax).to eq [0, Float::INFINITY] }
  specify('empty subexpression') { expect(ML.of(//).minmax).to eq [0, 0] }
  specify('anchor') { expect(ML.of(/^$/).minmax).to eq [0, 0] }
  specify('lookaround') { expect(ML.of(/(?=abc)/).minmax).to eq [0, 0] }
  specify('free space') { expect(ML.of(/   /x).minmax).to eq [0, 0] }
  specify('comment') { expect(ML.of(/(?#comment)/x).minmax).to eq [0, 0] }
  specify('backreference') { expect(ML.of(/(abc){2}\1/).minmax).to eq [9, 9] }
  specify('subexp call') { expect(ML.of(/(abc){2}\g<-1>/).minmax).to eq [9, 9] }
  specify('alternation') { expect(ML.of(/a|bcde/).minmax).to eq [1, 4] }
  specify('nested alternation') { expect(ML.of(/a|bc(d|efg)/).minmax).to eq [1, 5] }
  specify('quantified alternation') { expect(ML.of(/a|bcde?/).minmax).to eq [1, 4] }
  if ruby_version_at_least('2.4.1')
    specify('absence group') { expect(ML.of('(?~abc)').minmax).to eq [0, Float::INFINITY] }
  end

  specify('raises for missing references') do
    exp = RP.parse(/(a)\1/).last
    exp.referenced_expression = nil
    expect { exp.match_length }.to raise_error(ArgumentError)
  end

  describe('::of') do
    it('works with Regexps') { expect(ML.of(/foo/).minmax).to eq [3, 3] }
    it('works with Strings') { expect(ML.of('foo').minmax).to eq [3, 3] }
    it('works with Expressions') { expect(ML.of(RP.parse(/foo/)).minmax).to eq [3, 3] }
  end

  describe('Expression#match_length') do
    it('returns the MatchLength') { expect(RP.parse(/abc/).match_length.minmax).to eq [3, 3] }
  end

  describe('Expression#inner_match_length') do
    it 'returns the MatchLength of an expression that does not count towards parent match_length' do
      exp = RP.parse(/(?=ab|cdef)/)[0]
      expect(exp).to be_a Regexp::Expression::Assertion::Base
      expect(exp.match_length.minmax).to eq [0, 0]
      expect(exp.inner_match_length.minmax).to eq [2, 4]
    end
  end

  describe('#include?') do
    specify('unquantified') do
      expect(ML.of(/a/)).to include 1
      expect(ML.of(/a/)).not_to include 0
      expect(ML.of(/a/)).not_to include 2
    end

    specify('fixed quantified') do
      expect(ML.of(/a{5}/)).to include 5
      expect(ML.of(/a{5}/)).not_to include 0
      expect(ML.of(/a{5}/)).not_to include 4
      expect(ML.of(/a{5}/)).not_to include 6
    end

    specify('variably quantified') do
      expect(ML.of(/a?/)).to include 0
      expect(ML.of(/a?/)).to include 1
      expect(ML.of(/a?/)).not_to include 2
    end

    specify('nested quantified') do
      expect(ML.of(/(a{2}){3,4}/)).to include 6
      expect(ML.of(/(a{2}){3,4}/)).to include 8
      expect(ML.of(/(a{2}){3,4}/)).not_to include 0
      expect(ML.of(/(a{2}){3,4}/)).not_to include 5
      expect(ML.of(/(a{2}){3,4}/)).not_to include 7
      expect(ML.of(/(a{2}){3,4}/)).not_to include 9
    end

    specify('branches') do
      expect(ML.of(/ab|cdef/)).to include 2
      expect(ML.of(/ab|cdef/)).to include 4
      expect(ML.of(/ab|cdef/)).not_to include 0
      expect(ML.of(/ab|cdef/)).not_to include 3
      expect(ML.of(/ab|cdef/)).not_to include 5
    end

    specify('called on leaf node') do
      expect(ML.of(RP.parse(/a{2}/)[0])).to include 2
      expect(ML.of(RP.parse(/a{2}/)[0])).not_to include 0
      expect(ML.of(RP.parse(/a{2}/)[0])).not_to include 1
      expect(ML.of(RP.parse(/a{2}/)[0])).not_to include 3
    end
  end

  describe('#fixed?') do
    specify('unquantified') { expect(ML.of(/a/)).to be_fixed }
    specify('fixed quantified') { expect(ML.of(/a{5}/)).to be_fixed }
    specify('variably quantified') { expect(ML.of(/a?/)).not_to be_fixed }
    specify('equal branches') { expect(ML.of(/ab|cd/)).to be_fixed }
    specify('unequal branches') { expect(ML.of(/ab|cdef/)).not_to be_fixed }
    specify('equal quantified branches') { expect(ML.of(/a{2}|cd/)).to be_fixed }
    specify('unequal quantified branches') { expect(ML.of(/a{3}|cd/)).not_to be_fixed }
    specify('empty') { expect(ML.of(//)).to be_fixed }
  end

  describe('#each') do
    it 'returns an Enumerator if called without a block' do
      result = ML.of(/a?/).each
      expect(result).to be_a(Enumerator)
      expect(result.next).to eq 0
      expect(result.next).to eq 1
      expect { result.next }.to raise_error(StopIteration)
    end

    it 'is aware of limit option even if called without a block' do
      result = ML.of(/a?/).each(limit: 1)
      expect(result).to be_a(Enumerator)
      expect(result.next).to eq 0
      expect { result.next }.to raise_error(StopIteration)
    end

    it 'is limited to 1000 iterations in case there are infinite match lengths' do
      expect(ML.of(/a*/).first(3000).size).to eq 1000
    end

    it 'scaffolds the Enumerable interface' do
      expect(ML.of(/abc|defg/).count).to eq 2
      expect(ML.of(/(ab)*/).first(5)).to eq [0, 2, 4, 6, 8]
      expect(ML.of(/a{,10}/).any? { |len| len > 20 }).to be false
    end
  end

  describe('#endless_each') do
    it 'returns an Enumerator if called without a block' do
      result = ML.of(/a?/).endless_each
      expect(result).to be_a(Enumerator)
      expect(result.next).to eq 0
      expect(result.next).to eq 1
      expect { result.next }.to raise_error(StopIteration)
    end

    it 'never stops iterating for infinite match lengths' do
      expect(ML.of(/a*/).endless_each.first(3000).size).to eq 3000
    end
  end

  describe('#inspect') do
    it 'is nice' do
      result = RP.parse(/a{2,4}/)[0].match_length
      expect(result.inspect).to eq '#<Regexp::MatchLength<Literal> min=2 max=4>'
    end
  end
end
