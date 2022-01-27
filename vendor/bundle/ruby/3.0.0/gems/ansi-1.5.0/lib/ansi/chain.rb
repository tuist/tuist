require 'ansi/code'

module ANSI

  # ANSI::Chain was inspired by Kazuyoshi Tlacaelel's Isna library.
  #
  class Chain

    #
    def initialize(string)
      @string = string.to_s
      @codes  = []
    end

    #
    attr :string

    #
    attr :codes

    #
    def method_missing(s, *a, &b)
      if ANSI::CHART.key?(s)
        @codes << s
        self
      else
        super(s, *a, &b)
      end
    end

    #
    def to_s
      if codes.empty?
        result = @string
      else
        result = Code.ansi(@string, *codes)
        codes.clear
      end
      result
    end

    #
    def to_str
      to_s
    end

  end

end

