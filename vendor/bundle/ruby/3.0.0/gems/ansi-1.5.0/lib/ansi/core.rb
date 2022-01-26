require 'ansi/code'
require 'ansi/chain'

class ::String

  #
  def ansi(*codes)
    if codes.empty?
      ANSI::Chain.new(self)
    else
      ANSI::Code.ansi(self, *codes)
    end
  end

  #
  def ansi!(*codes)
    replace(ansi(*codes))
  end

  #
  def unansi
    ANSI::Code.unansi(self)
  end

  #
  def unansi!
    replace(unansi)
  end
end

