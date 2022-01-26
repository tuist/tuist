module Regexp::Syntax
  class V2_4_0 < Regexp::Syntax::V2_3
    def initialize
      super

      implements :property,    UnicodeProperty::V2_4_0
      implements :nonproperty, UnicodeProperty::V2_4_0
    end
  end
end
