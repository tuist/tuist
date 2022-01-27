require 'spec_helper'

RSpec.describe(Regexp::Syntax::V2_2_0) do
  include_examples 'syntax', Regexp::Syntax.new('ruby/2.2.0'),
  implements: {
    property: T::UnicodeProperty::Script_V2_2_0 + T::UnicodeProperty::Age_V2_2_0,
    nonproperty: T::UnicodeProperty::Script_V2_2_0 + T::UnicodeProperty::Age_V2_2_0
  }
end
