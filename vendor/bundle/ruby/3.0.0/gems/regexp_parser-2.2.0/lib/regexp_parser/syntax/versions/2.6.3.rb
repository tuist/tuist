module Regexp::Syntax
  class V2_6_3 < Regexp::Syntax::V2_6_2
    def initialize
      super

      implements :property,    UnicodeProperty::V2_6_3
      implements :nonproperty, UnicodeProperty::V2_6_3
    end
  end
end
