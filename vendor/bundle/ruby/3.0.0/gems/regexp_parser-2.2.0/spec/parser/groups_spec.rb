require 'spec_helper'

RSpec.describe('Group parsing') do
  include_examples 'parse', /(?=abc)(?!def)/,
    0 => [:assertion, :lookahead,   Assertion::Lookahead],
    1 => [:assertion, :nlookahead,  Assertion::NegativeLookahead]

  include_examples 'parse', /(?<=abc)(?<!def)/,
    0 => [:assertion, :lookbehind,  Assertion::Lookbehind],
    1 => [:assertion, :nlookbehind, Assertion::NegativeLookbehind]

  include_examples 'parse', /a(?# is for apple)b(?# for boy)c(?# cat)/,
    1 => [:group, :comment, Group::Comment],
    3 => [:group, :comment, Group::Comment],
    5 => [:group, :comment, Group::Comment]

  if ruby_version_at_least('2.4.1')
    include_examples 'parse', 'a(?~b)c(?~d)e',
      1 => [:group, :absence, Group::Absence],
      3 => [:group, :absence, Group::Absence]
  end

  include_examples 'parse', /(?m:a)/,
    0 => [:group, :options, Group::Options, options: { m: true }, option_changes: { m: true }]

  # self-defeating group option
  include_examples 'parse', /(?m-m:a)/,
    0 => [:group, :options, Group::Options, options: {}, option_changes: { m: false }]

  # activate one option in nested group
  include_examples 'parse', /(?x-mi:a(?m:b))/,
    0      => [:group, :options, Group::Options, options: { x: true }, option_changes: { i: false, m: false, x: true }],
    [0, 1] => [:group, :options, Group::Options, options: { m: true, x: true }, option_changes: { m: true }]

  # deactivate one option in nested group
  include_examples 'parse', /(?ix-m:a(?-i:b))/,
    0      => [:group, :options, Group::Options, options: { i: true, x: true }, option_changes: { i: true, m: false, x: true }],
    [0, 1] => [:group, :options, Group::Options, options: { x: true }, option_changes: { i: false }]

  # invert all options in nested group
  include_examples 'parse', /(?xi-m:a(?m-ix:b))/,
    0      => [:group, :options, Group::Options, options: { i: true, x: true }, option_changes: { i: true, m: false, x: true }],
    [0, 1] => [:group, :options, Group::Options, options: { m: true }, option_changes: { i: false, m: true, x: false }]

  # nested options affect literal subexpressions
  include_examples 'parse', /(?x-mi:a(?m:b))/,
    [0, 0]    => [:literal, :literal, Literal, text: 'a', options: { x: true }],
    [0, 1, 0] => [:literal, :literal, Literal, text: 'b', options: { m: true, x: true }]

  # option switching group
  include_examples 'parse', /a(?i-m)b/m,
    0 => [:literal, :literal,         Literal,        text: 'a', options: { m: true }],
    1 => [:group,   :options_switch,  Group::Options, options: { i: true }, option_changes: { i: true, m: false }],
    2 => [:literal, :literal,         Literal,        text: 'b', options: { i: true }]

  # option switch in group
  include_examples 'parse', /(a(?i-m)b)c/m,
    0      => [:group,   :capture,        Group::Capture, options: { m: true }],
    [0, 0] => [:literal, :literal,        Literal,        text: 'a', options: { m: true }],
    [0, 1] => [:group,   :options_switch, Group::Options, options: { i: true }, option_changes: { i: true, m: false }],
    [0, 2] => [:literal, :literal,        Literal,        text: 'b', options: { i: true }],
    1      => [:literal, :literal,        Literal,        text: 'c', options: { m: true }]

  # nested option switch in group
  include_examples 'parse', /((?i-m)(a(?-i)b))/m,
    [0, 1]    => [:group,   :capture,        Group::Capture, options: { i: true }],
    [0, 1, 0] => [:literal, :literal,        Literal,        text: 'a', options: { i: true }],
    [0, 1, 1] => [:group,   :options_switch, Group::Options, options: {}, option_changes: { i: false }],
    [0, 1, 2] => [:literal, :literal,        Literal,        text: 'b', options: {}]

  # options dau
  include_examples 'parse', /(?dua:abc)/,
    0 => [:group, :options, Group::Options, options: { a: true }, option_changes: { a: true }]

  # nested options dau
  include_examples 'parse', /(?u:a(?d:b))/,
    0         => [:group,   :options, Group::Options, options: { u: true }, option_changes: { u: true }],
    [0, 1]    => [:group,   :options, Group::Options, options: { d: true }, option_changes: { d: true, u: false }],
    [0, 1, 0] => [:literal, :literal, Literal,        text: 'b', options: { d: true }]

  # nested options da
  include_examples 'parse', /(?di-xm:a(?da-x:b))/,
    0         => [:group,   :options, Group::Options, options: { d: true, i:true }],
    [0, 1]    => [:group,   :options, Group::Options, options: { a: true, i: true }, option_changes: { a: true, d: false, x: false}],
    [0, 1, 0] => [:literal, :literal, Literal,        text: 'b', options: { a: true, i: true }]

  specify('parse group number') do
    root = RP.parse(/(a)(?=b)((?:c)(d|(e)))/)

    expect(root[0].number).to eq 1
    expect(root[1]).not_to respond_to(:number)
    expect(root[2].number).to eq 2
    expect(root[2][0]).not_to respond_to(:number)
    expect(root[2][1].number).to eq 3
    expect(root[2][1][0][1][0].number).to eq 4
  end

  specify('parse group number at level') do
    root = RP.parse(/(a)(?=b)((?:c)(d|(e)))/)

    expect(root[0].number_at_level).to eq 1
    expect(root[1]).not_to respond_to(:number_at_level)
    expect(root[2].number_at_level).to eq 2
    expect(root[2][0]).not_to respond_to(:number_at_level)
    expect(root[2][1].number_at_level).to eq 1
    expect(root[2][1][0][1][0].number_at_level).to eq 1
  end
end
