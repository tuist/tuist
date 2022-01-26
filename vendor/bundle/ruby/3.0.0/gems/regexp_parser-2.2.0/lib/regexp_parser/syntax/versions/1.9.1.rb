module Regexp::Syntax
  class V1_9_1 < Regexp::Syntax::V1_8_6
    def initialize
      super

      implements :assertion, Assertion::Lookbehind
      implements :backref, Backreference::All + SubexpressionCall::All
      implements :posixclass, PosixClass::Extensions
      implements :nonposixclass, PosixClass::All
      implements :escape, Escape::Unicode + Escape::Hex + Escape::Octal
      implements :type, CharacterType::Hex
      implements :property, UnicodeProperty::V1_9_0
      implements :nonproperty, UnicodeProperty::V1_9_0
      implements :quantifier,
        Quantifier::Possessive + Quantifier::IntervalPossessive
    end
  end
end
