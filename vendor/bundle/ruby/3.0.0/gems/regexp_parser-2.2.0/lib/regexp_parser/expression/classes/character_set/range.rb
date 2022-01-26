module Regexp::Expression
  class CharacterSet < Regexp::Expression::Subexpression
    class Range < Regexp::Expression::Subexpression
      def starts_at
        expressions.first.starts_at
      end
      alias :ts :starts_at

      def <<(exp)
        complete? and raise Regexp::Parser::Error,
          "Can't add more than 2 expressions to a Range"
        super
      end

      def complete?
        count == 2
      end

      def to_s(_format = :full)
        expressions.join(text)
      end
    end
  end
end
