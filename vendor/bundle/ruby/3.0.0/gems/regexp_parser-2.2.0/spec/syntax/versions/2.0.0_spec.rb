require 'spec_helper'

RSpec.describe(Regexp::Syntax::V2_0_0) do
  include_examples 'syntax', Regexp::Syntax.new('ruby/2.0.0'),
  implements: {
    property: T::UnicodeProperty::Age_V2_0_0,
    nonproperty: T::UnicodeProperty::Age_V2_0_0
  },
  excludes: {
    property: %i[newline],
    nonproperty: %i[newline]
  }
end
