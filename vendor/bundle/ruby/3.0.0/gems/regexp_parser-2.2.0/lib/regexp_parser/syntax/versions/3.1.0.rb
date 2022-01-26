module Regexp::Syntax
  class V3_1_0 < Regexp::Syntax::V2_6_3
    def initialize
      super

      implements :property,    UnicodeProperty::V3_1_0
      implements :nonproperty, UnicodeProperty::V3_1_0
    end
  end
end
