module Regexp::Syntax
  class V2_2_0 < Regexp::Syntax::V2_1
    def initialize
      super

      implements :property,    UnicodeProperty::V2_2_0
      implements :nonproperty, UnicodeProperty::V2_2_0
    end
  end
end
