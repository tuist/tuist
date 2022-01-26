require 'ansi/code'
#require 'ansi/layout/split'

# Create a new Ansi::String object.
def ANSI.string(str)
  ANSI::String.new(str)
end

# IMPORTANT! ANSI::String is experimental!!!
#
# ANSI::String stores a regular string (`@text`) and an associative
# array that ties a character index to an ANSI code (`marks`).
# For example is we have the string:
#
#   "Big Apple"
#
# And applied the color red to it, the marks list would be:
#
#   [[0, :red], [9, :clear]]
#
# TODO: In the future we may be able to subclass String,
# instead of delegating via @text, but not until it is more
# compatible.
#
class ANSI::String

  CLR = ANSI::Code::CLEAR

  attr :text
  attr :marks

  # New Ansi::String
  def initialize(text=nil, marks=nil)
    @text  = (text  || '').to_s
    @marks = marks  || []
    yield(self) if block_given?
  end

  # Convert Ansi::String object to normal String.
  # This converts the intental markup codes to ANSI codes.
  def to_s
    s = text.dup
    m = marks.sort do |a,b|
      v = b[0] <=> a[0]
      if v == 0
        (b[1] == :clear or b[1] == :reset) ? -1 : 1
      else
        v
      end
    end
    m.each do |(index, code)|
      s.insert(index, ANSI::Code.__send__(code))
    end
    #s << CLR unless s =~ /#{Regexp.escape(CLR)}$/  # always end with a clear
    s
  end

  # ANSI::String is a type of String.
  alias_method :to_str, :to_s

  # The size of the base text.
  def size ; text.size ; end

  # Upcase the string.
  def upcase  ; self.class.new(text.upcase, marks) ; end
  def upcase! ; text.upcase! ; end

  # Downcase the string.
  def downcase  ; self.class.new(text.downcase, marks) ; end
  def downcase! ; text.upcase! ; end

  # Add one String to another, or to a regular String.
  def +(other)
    case other
    when ANSI::String
      ntext  = text + other.text
      nmarks = marks.dup
      omarks = shift_marks(0, text.size, other.marks)
      omarks.each{ |(i, c)| nmarks << [i,c] }
    else
      ntext  = text + other.to_s
      nmarks = marks.dup
    end
    self.class.new(ntext, nmarks)
  end

  #
  #def |(other)
  #  Split.new(self, other)
  #end

  #
  #def lr(other, options={})
  #  Split.new(self, other, options)
  #end

  # slice
  def slice(*args)
    if args.size == 2
      index, len = *args
      endex  = index+len
      new_text  = text[index, len]
      new_marks = []
      marks.each do |(i, v)|
        new_marks << [i, v] if i >= index && i < endex
      end
      self.class.new(new_text, new_marks)
    elsif args.size == 1
      rng = args.first
      case rng
      when Range
        index, endex = rng.begin, rng.end
        new_text  = text[rng]
        new_marks = []
        marks.each do |(i, v)|
          new_marks << [i, v] if i >= index && i < endex
        end
        self.class.new(new_text, new_marks)
      else
        nm = marks.select do |(i, v)|
          #marks[0] == rng or ( marks[0] == rng + 1 && [:clear, :reset].include?(marks[1]) )
          i == rng or ( i == rng + 1 && [:clear, :reset].include?(v) )
        end
        self.class.new(text[rng,1], nm)
      end
    else
      raise ArgumentError
    end
  end

  #
  alias_method :[], :slice

  # This is more limited than the normal String method.
  # It does not yet support a block, and +replacement+
  # won't substitue for \1, \2, etc.
  #
  # TODO: block support.
  def sub!(pattern, replacement=nil, &block)
    mark_changes = []
    text = @text.sub(pattern) do |s|
      index  = $~.begin(0)
      replacement = block.call(s) if block_given?
      delta  = (replacement.size - s.size)
      mark_changes << [index, delta]
      replacement
    end
    marks = @marks
    mark_changes.each do |index, delta|
      marks = shift_marks(index, delta, marks)
    end
    @text  = text
    @marks = marks
    self
  end

  # See #sub!.
  def sub(pattern,replacement=nil, &block)
    dup.sub!(pattern, replacement, &block)
  end

  #
  def gsub!(pattern, replacement=nil, &block)
    mark_changes   = []
    mark_additions = []
    text = @text.gsub(pattern) do |s|
      index = $~.begin(0)
      replacement = block.call(self.class.new(s)) if block_given?
      if self.class===replacement
        adj_marks = replacement.marks.map{ |(i,c)| [i+index,c] }
        mark_additions.concat(adj_marks)
        replacement = replacement.text
      end
      delta = (replacement.size - s.size)
      mark_changes << [index, delta]
      replacement
    end
    marks = @marks
    mark_changes.each do |(index, delta)|
      marks = shift_marks(index, delta, marks)
    end
    marks.concat(mark_additions)
    @text  = text
    @marks = marks
    self
  end

  # See #gsub!.
  def gsub(pattern, replacement=nil, &block)
    dup.gsub!(pattern, replacement, &block)
  end

  #
  def ansi(code)
    m = marks.dup
    m.unshift([0, code])
    m.push([size, :clear])
    self.class.new(text, m)
  end

  alias_method :color, :ansi

  #
  def ansi!(code)
    marks.unshift([0, code])
    marks.push([size, :clear])
  end

  alias_method :color!, :ansi!

  def red        ; color(:red)      ; end
  def green      ; color(:green)    ; end
  def blue       ; color(:blue)     ; end
  def black      ; color(:black)    ; end
  def magenta    ; color(:magenta)  ; end
  def yellow     ; color(:yellow)   ; end
  def cyan       ; color(:cyan)     ; end

  def bold       ; ansi(:bold)       ; end
  def underline  ; ansi(:underline)  ; end

  def red!       ; color!(:red)     ; end
  def green!     ; color!(:green)   ; end
  def blue!      ; color!(:blue)    ; end
  def black!     ; color!(:black)   ; end
  def magenta!   ; color!(:magenta) ; end
  def yellow!    ; color!(:yellow)  ; end
  def cyan!      ; color!(:cyan)    ; end

  def bold!      ; ansi!(:bold)      ; end
  def underline! ; ansi!(:underline) ; end

private

  #
  def shift_marks(index, delta, marks=nil)
    new_marks = []
    (marks || @marks).each do |(i, c)|
      case i <=> index
      when -1
        new_marks << [i, c]
      when 0, 1
        new_marks << [i+delta, c]
      end
    end
    new_marks
  end

  #
  def shift_marks!(index, delta)
    @marks.replace(shift_marks(index, delta))
  end

end
