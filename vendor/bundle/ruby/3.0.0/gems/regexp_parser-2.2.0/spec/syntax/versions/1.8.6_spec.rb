require 'spec_helper'

RSpec.describe(Regexp::Syntax::V1_8_6) do
  include_examples 'syntax', Regexp::Syntax.new('ruby/1.8.6'),
  implements: {
    assertion: T::Assertion::Lookahead,
    backref: T::Backreference::Plain,
    escape: T::Escape::Basic + T::Escape::ASCII + T::Escape::Meta + T::Escape::Control,
    group: T::Group::V1_8_6,
    quantifier: T::Quantifier::Greedy + T::Quantifier::Reluctant + T::Quantifier::Interval + T::Quantifier::IntervalReluctant
  },
  excludes: {
    assertion: T::Assertion::Lookbehind,
    backref: T::Backreference::All - T::Backreference::Plain + T::SubexpressionCall::All,
    quantifier: T::Quantifier::Possessive
  }
end
