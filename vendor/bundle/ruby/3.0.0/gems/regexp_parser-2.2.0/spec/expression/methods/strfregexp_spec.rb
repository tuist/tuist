require 'spec_helper'

RSpec.describe('Expression#strfregexp') do
  specify('#strfre alias') do
    expect(RP.parse(/a/)).to respond_to(:strfre)
  end

  specify('#strfregexp level') do
    root = RP.parse(/a(b(c))/)

    expect(root.strfregexp('%l')).to eq 'root'

    a = root.first
    expect(a.strfregexp('%%l')).to eq '%0'

    b = root[1].first
    expect(b.strfregexp('<%l>')).to eq '<1>'

    c = root[1][1].first
    expect(c.strfregexp('[at: %l]')).to eq '[at: 2]'
  end

  specify('#strfregexp start end') do
    root = RP.parse(/a(b(c))/)

    expect(root.strfregexp('%s')).to eq '0'
    expect(root.strfregexp('%e')).to eq '7'

    a = root.first
    expect(a.strfregexp('%%s')).to eq '%0'
    expect(a.strfregexp('%e')).to eq '1'

    group_1 = root[1]
    expect(group_1.strfregexp('GRP:%s')).to eq 'GRP:1'
    expect(group_1.strfregexp('%e')).to eq '7'

    b = group_1.first
    expect(b.strfregexp('<@%s>')).to eq '<@2>'
    expect(b.strfregexp('%e')).to eq '3'

    c = group_1.last.first
    expect(c.strfregexp('[at: %s]')).to eq '[at: 4]'
    expect(c.strfregexp('%e')).to eq '5'
  end

  specify('#strfregexp length') do
    root = RP.parse(/a[b]c/)

    expect(root.strfregexp('%S')).to eq '5'

    a = root.first
    expect(a.strfregexp('%S')).to eq '1'

    set = root[1]
    expect(set.strfregexp('%S')).to eq '3'
  end

  specify('#strfregexp coded offset') do
    root = RP.parse(/a[b]c/)

    expect(root.strfregexp('%o')).to eq '@0+5'

    a = root.first
    expect(a.strfregexp('%o')).to eq '@0+1'

    set = root[1]
    expect(set.strfregexp('%o')).to eq '@1+3'
  end

  specify('#strfregexp type token') do
    root = RP.parse(/a[b](c)/)

    expect(root.strfregexp('%y')).to eq 'expression'
    expect(root.strfregexp('%k')).to eq 'root'
    expect(root.strfregexp('%i')).to eq 'expression:root'
    expect(root.strfregexp('%c')).to eq 'Regexp::Expression::Root'

    a = root.first
    expect(a.strfregexp('%y')).to eq 'literal'
    expect(a.strfregexp('%k')).to eq 'literal'
    expect(a.strfregexp('%i')).to eq 'literal:literal'
    expect(a.strfregexp('%c')).to eq 'Regexp::Expression::Literal'

    set = root[1]
    expect(set.strfregexp('%y')).to eq 'set'
    expect(set.strfregexp('%k')).to eq 'character'
    expect(set.strfregexp('%i')).to eq 'set:character'
    expect(set.strfregexp('%c')).to eq 'Regexp::Expression::CharacterSet'

    group = root.last
    expect(group.strfregexp('%y')).to eq 'group'
    expect(group.strfregexp('%k')).to eq 'capture'
    expect(group.strfregexp('%i')).to eq 'group:capture'
    expect(group.strfregexp('%c')).to eq 'Regexp::Expression::Group::Capture'
  end

  specify('#strfregexp quantifier') do
    root = RP.parse(/a+[b](c)?d{3,4}/)

    expect(root.strfregexp('%q')).to eq '{1}'
    expect(root.strfregexp('%Q')).to eq ''
    expect(root.strfregexp('%z, %Z')).to eq '1, 1'

    a = root.first
    expect(a.strfregexp('%q')).to eq '{1, or-more}'
    expect(a.strfregexp('%Q')).to eq '+'
    expect(a.strfregexp('%z, %Z')).to eq '1, -1'

    set = root[1]
    expect(set.strfregexp('%q')).to eq '{1}'
    expect(set.strfregexp('%Q')).to eq ''
    expect(set.strfregexp('%z, %Z')).to eq '1, 1'

    group = root[2]
    expect(group.strfregexp('%q')).to eq '{0, 1}'
    expect(group.strfregexp('%Q')).to eq '?'
    expect(group.strfregexp('%z, %Z')).to eq '0, 1'

    d = root.last
    expect(d.strfregexp('%q')).to eq '{3, 4}'
    expect(d.strfregexp('%Q')).to eq '{3,4}'
    expect(d.strfregexp('%z, %Z')).to eq '3, 4'
  end

  specify('#strfregexp text') do
    root = RP.parse(/a(b(c))|[d-gk-p]+/)

    expect(root.strfregexp('%t')).to eq 'a(b(c))|[d-gk-p]+'
    expect(root.strfregexp('%~t')).to eq 'expression:root'

    alt = root.first
    expect(alt.strfregexp('%t')).to eq 'a(b(c))|[d-gk-p]+'
    expect(alt.strfregexp('%T')).to eq 'a(b(c))|[d-gk-p]+'
    expect(alt.strfregexp('%~t')).to eq 'meta:alternation'

    seq_1 = alt.first
    expect(seq_1.strfregexp('%t')).to eq 'a(b(c))'
    expect(seq_1.strfregexp('%T')).to eq 'a(b(c))'
    expect(seq_1.strfregexp('%~t')).to eq 'expression:sequence'

    group = seq_1[1]
    expect(group.strfregexp('%t')).to eq '(b(c))'
    expect(group.strfregexp('%T')).to eq '(b(c))'
    expect(group.strfregexp('%~t')).to eq 'group:capture'

    seq_2 = alt.last
    expect(seq_2.strfregexp('%t')).to eq '[d-gk-p]+'
    expect(seq_2.strfregexp('%T')).to eq '[d-gk-p]+'

    set = seq_2.first
    expect(set.strfregexp('%t')).to eq '[d-gk-p]'
    expect(set.strfregexp('%T')).to eq '[d-gk-p]+'
    expect(set.strfregexp('%~t')).to eq 'set:character'
  end

  specify('#strfregexp combined') do
    root = RP.parse(/a{5}|[b-d]+/)

    expect(root.strfregexp('%b')).to eq '@0+11 expression:root'
    expect(root.strfregexp('%b')).to eq root.strfregexp('%o %i')

    expect(root.strfregexp('%m')).to eq '@0+11 expression:root {1}'
    expect(root.strfregexp('%m')).to eq root.strfregexp('%b %q')

    expect(root.strfregexp('%a')).to eq '@0+11 expression:root {1} a{5}|[b-d]+'
    expect(root.strfregexp('%a')).to eq root.strfregexp('%m %t')
  end

  specify('#strfregexp conditional') do
    root = RP.parse('(?<A>a)(?(<A>)b|c)', 'ruby/2.0')

    expect { root.strfregexp }.not_to(raise_error)
  end

  specify('#strfregexp_tree') do
    root = RP.parse(/a[b-d]*(e(f+))?/)

    expect(root.strfregexp_tree('%>%o %~t')).to eq(
      "@0+15 expression:root\n" +
      "  @0+1 a\n" +
      "  @1+6 set:character\n" +
      "    @2+3 set:range\n" +
      "      @2+1 b\n" +
      "      @4+1 d\n" +
      "  @7+8 group:capture\n" +
      "    @8+1 e\n" +
      "    @9+4 group:capture\n" +
      "      @10+2 f+"
    )
  end

  specify('#strfregexp_tree separator') do
    root = RP.parse(/a[b-d]*(e(f+))?/)

    expect(root.strfregexp_tree('%>%o %~t', true, '-SEP-')).to eq(
      "@0+15 expression:root-SEP-" +
      "  @0+1 a-SEP-" +
      "  @1+6 set:character-SEP-" +
      "    @2+3 set:range-SEP-" +
      "      @2+1 b-SEP-" +
      "      @4+1 d-SEP-" +
      "  @7+8 group:capture-SEP-" +
      "    @8+1 e-SEP-" +
      "    @9+4 group:capture-SEP-" +
      "      @10+2 f+"
    )
  end

  specify('#strfregexp_tree excluding self') do
    root = RP.parse(/a[b-d]*(e(f+))?/)

    expect(root.strfregexp_tree('%>%o %~t', false)).to eq(
      "@0+1 a\n" +
      "@1+6 set:character\n" +
      "  @2+3 set:range\n" +
      "    @2+1 b\n" +
      "    @4+1 d\n" +
      "@7+8 group:capture\n" +
      "  @8+1 e\n" +
      "  @9+4 group:capture\n" +
      "    @10+2 f+"
    )
  end
end
