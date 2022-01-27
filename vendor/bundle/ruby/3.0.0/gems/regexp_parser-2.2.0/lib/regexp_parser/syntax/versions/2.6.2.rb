module Regexp::Syntax
  class V2_6_2 < Regexp::Syntax::V2_6_0
    def initialize
      super

      implements :property,    UnicodeProperty::V2_6_2
      implements :nonproperty, UnicodeProperty::V2_6_2
    end
  end
end
