module Regexp::Syntax
  module Token
    module Backreference
      Plain     = %i[number]
      Number    = Plain + %i[number_ref number_rel_ref]
      Name      = %i[name_ref]

      RecursionLevel = %i[name_recursion_ref number_recursion_ref]

      All = Name + Number + RecursionLevel
      Type = :backref
    end

    # Type is the same as Backreference so keeping it here, for now.
    module SubexpressionCall
      Name      = %i[name_call]
      Number    = %i[number_call number_rel_call]

      All = Name + Number
    end

    Map[Backreference::Type] = Backreference::All +
                               SubexpressionCall::All
  end
end
