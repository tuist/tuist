module Regexp::Expression
  module Conditional
    class TooManyBranches < Regexp::Parser::Error
      def initialize
        super('The conditional expression has more than 2 branches')
      end
    end

    class Condition < Regexp::Expression::Base
      attr_accessor :referenced_expression

      # Name or number of the referenced capturing group that determines state.
      # Returns a String if reference is by name, Integer if by number.
      def reference
        ref = text.tr("'<>()", "")
        ref =~ /\D/ ? ref : Integer(ref)
      end

      def initialize_copy(orig)
        self.referenced_expression = orig.referenced_expression.dup
        super
      end
    end

    class Branch < Regexp::Expression::Sequence; end

    class Expression < Regexp::Expression::Subexpression
      attr_accessor :referenced_expression

      def <<(exp)
        expressions.last << exp
      end

      def add_sequence(active_opts = {})
        raise TooManyBranches.new if branches.length == 2
        params = { conditional_level: conditional_level + 1 }
        Branch.add_to(self, params, active_opts)
      end
      alias :branch :add_sequence

      def condition=(exp)
        expressions.delete(condition)
        expressions.unshift(exp)
      end

      def condition
        find { |subexp| subexp.is_a?(Condition) }
      end

      def branches
        select { |subexp| subexp.is_a?(Sequence) }
      end

      def reference
        condition.reference
      end

      def to_s(format = :full)
        "#{text}#{condition}#{branches.join('|')})#{quantifier_affix(format)}"
      end

      def initialize_copy(orig)
        self.referenced_expression = orig.referenced_expression.dup
        super
      end
    end
  end
end
