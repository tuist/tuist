module Regexp::Expression
  class Quantifier
    MODES = %i[greedy possessive reluctant]

    attr_reader :token, :text, :min, :max, :mode

    def initialize(token, text, min, max, mode)
      @token = token
      @text  = text
      @mode  = mode
      @min   = min
      @max   = max
    end

    def initialize_copy(orig)
      @text = orig.text.dup
      super
    end

    def to_s
      text.dup
    end
    alias :to_str :to_s

    def to_h
      {
        token: token,
        text:  text,
        mode:  mode,
        min:   min,
        max:   max,
      }
    end

    MODES.each do |mode|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{mode}?
          mode.equal?(:#{mode})
        end
      RUBY
    end
    alias :lazy? :reluctant?

    def ==(other)
      other.class == self.class &&
        other.token == token &&
        other.mode == mode &&
        other.min == min &&
        other.max == max
    end
    alias :eq :==
  end
end
