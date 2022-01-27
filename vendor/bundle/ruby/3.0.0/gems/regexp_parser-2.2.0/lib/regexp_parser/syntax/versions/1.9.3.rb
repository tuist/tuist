module Regexp::Syntax
  class V1_9_3 < Regexp::Syntax::V1_9_1
    def initialize
      super

      # these were added with update of Oniguruma to Unicode 6.0
      implements :property,    UnicodeProperty::V1_9_3
      implements :nonproperty, UnicodeProperty::V1_9_3
    end
  end
end
