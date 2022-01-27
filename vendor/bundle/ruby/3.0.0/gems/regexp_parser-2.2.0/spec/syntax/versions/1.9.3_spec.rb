require 'spec_helper'

RSpec.describe(Regexp::Syntax::V1_9_3) do
  include_examples 'syntax', Regexp::Syntax.new('ruby/1.9.3'),
  implements: {
    property: T::UnicodeProperty::Script_V1_9_3 + T::UnicodeProperty::Age_V1_9_3,
    nonproperty: T::UnicodeProperty::Script_V1_9_3 + T::UnicodeProperty::Age_V1_9_3
  }
end
