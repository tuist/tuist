module Naturally
  # An entity which can be compared to other like elements for
  # sorting. It's an object representing
  # a value which implements the {Comparable} interface which can
  # convert itself to an array.
  class Segment
    include Comparable

    def initialize(v)
      @val = v
    end

    def <=>(other)
      to_array <=> other.to_array
    end

    # @return [Array] a representation of myself in array form
    #                 which enables me to be compared against
    #                 another instance for sorting.
    #                 The array is prepended with a symbol so
    #                 two arrays are always comparable.
    #
    # @example a simple number
    #   Segment.new('10').to_array #=> [:int, 10]
    #
    # @example a college course code
    #   Segment.new('MATH101').to_array #=> [:str, "MATH", 101]
    #
    # @example Section 633a of the U.S. Age Discrimination in Employment Act
    #   Segment.new('633a').to_array #=> [:int, 633, "a"]
    def to_array
      # TODO: Refactor, probably via polymorphism
      if @val =~ /^(\p{Digit}+)(\p{Alpha}+)$/
        [:int, $1.to_i, $2]
      elsif @val =~ /^(\p{Alpha}+)(\p{Digit}+)$/
        [:str, $1, $2.to_i]
      elsif @val =~ /^\p{Digit}+$/
        [:int, @val.to_i]
      else
        [:str, @val]
      end
    end
  end
end
