module Regexp::Expression
  class FreeSpace < Regexp::Expression::Base
    def quantify(_token, _text, _min = nil, _max = nil, _mode = :greedy)
      raise Regexp::Parser::Error, 'Can not quantify a free space object'
    end
  end

  class Comment < Regexp::Expression::FreeSpace; end

  class WhiteSpace < Regexp::Expression::FreeSpace
    def merge(exp)
      text << exp.text
    end
  end
end
