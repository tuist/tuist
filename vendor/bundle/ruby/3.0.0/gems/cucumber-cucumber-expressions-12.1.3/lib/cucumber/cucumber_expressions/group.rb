module Cucumber
  module CucumberExpressions
    class Group
      attr_reader :value, :start, :end, :children

      def initialize(value, start, _end, children)
        @value = value
        @start = start
        @end = _end
        @children = children
      end

      def values
        (children.empty? ? [self] : children).map(&:value)
      end
    end
  end
end
