module Regexp::Syntax
  class V2_5_0 < Regexp::Syntax::V2_4
    def initialize
      super

      implements :property,    UnicodeProperty::V2_5_0
      implements :nonproperty, UnicodeProperty::V2_5_0
    end
  end
end
