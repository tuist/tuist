module Regexp::Syntax
  class V2_6_0 < Regexp::Syntax::V2_5
    def initialize
      super

      implements :property,    UnicodeProperty::V2_6_0
      implements :nonproperty, UnicodeProperty::V2_6_0
    end
  end
end
