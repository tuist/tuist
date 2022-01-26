module Regexp::Expression
  class Base
    attr_accessor :type, :token
    attr_accessor :text, :ts
    attr_accessor :level, :set_level, :conditional_level, :nesting_level

    attr_accessor :quantifier
    attr_accessor :options

    def initialize(token, options = {})
      self.type              = token.type
      self.token             = token.token
      self.text              = token.text
      self.ts                = token.ts
      self.level             = token.level
      self.set_level         = token.set_level
      self.conditional_level = token.conditional_level
      self.nesting_level     = 0
      self.quantifier        = nil
      self.options           = options
    end

    def initialize_copy(orig)
      self.text       = (orig.text       ? orig.text.dup         : nil)
      self.options    = (orig.options    ? orig.options.dup      : nil)
      self.quantifier = (orig.quantifier ? orig.quantifier.clone : nil)
      super
    end

    def to_re(format = :full)
      ::Regexp.new(to_s(format))
    end

    alias :starts_at :ts

    def base_length
      to_s(:base).length
    end

    def full_length
      to_s.length
    end

    def offset
      [starts_at, full_length]
    end

    def coded_offset
      '@%d+%d' % offset
    end

    def to_s(format = :full)
      "#{text}#{quantifier_affix(format)}"
    end

    def quantifier_affix(expression_format)
      quantifier.to_s if quantified? && expression_format != :base
    end

    def terminal?
      !respond_to?(:expressions)
    end

    def quantify(token, text, min = nil, max = nil, mode = :greedy)
      self.quantifier = Quantifier.new(token, text, min, max, mode)
    end

    def unquantified_clone
      clone.tap { |exp| exp.quantifier = nil }
    end

    def quantified?
      !quantifier.nil?
    end

    # Deprecated. Prefer `#repetitions` which has a more uniform interface.
    def quantity
      return [nil,nil] unless quantified?
      [quantifier.min, quantifier.max]
    end

    def repetitions
      return 1..1 unless quantified?
      min = quantifier.min
      max = quantifier.max < 0 ? Float::INFINITY : quantifier.max
      range = min..max
      # fix Range#minmax on old Rubies - https://bugs.ruby-lang.org/issues/15807
      if RUBY_VERSION.to_f < 2.7
        range.define_singleton_method(:minmax) { [min, max] }
      end
      range
    end

    def greedy?
      quantified? and quantifier.greedy?
    end

    def reluctant?
      quantified? and quantifier.reluctant?
    end
    alias :lazy? :reluctant?

    def possessive?
      quantified? and quantifier.possessive?
    end

    def attributes
      {
        type:              type,
        token:             token,
        text:              to_s(:base),
        starts_at:         ts,
        length:            full_length,
        level:             level,
        set_level:         set_level,
        conditional_level: conditional_level,
        options:           options,
        quantifier:        quantified? ? quantifier.to_h : nil,
      }
    end
    alias :to_h :attributes
  end
end
