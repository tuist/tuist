module ANSI

  require 'ansi/code'

  # TODO: split dump method into two parts, the first should create a hex table
  # then the second, #dump method, will print it out.

  # Create a colorized hex dump of byte string.
  # 
  # Output looks something like the following, but colorized.
  # 
  #   000352c0:  ed 33 8c 85 6e cc f6 f7  72 79 1c e3 3a b4 c2 c6  |.3..n...ry..:...|
  #   000352d0:  c8 8d d6 ee 3e 68 a1 a5  ae b2 b7 97 a4 1d 5f a7  |....>h........_.|
  #   000352e0:  d8 7d 28 db f6 8a e7 8a  7b 8d 0b bd 35 7d 25 3c  |.}(.....{...5}%<|
  #   000352f0:  8b 3c c8 9d ec 04 85 54  92 a0 f7 a8 ed cf 05 7d  |.<.....T.......}|
  #   00035300:  b5 e3 9e 35 f0 79 9f 51  74 e3 60 ee 0f 03 8e 3f  |...5.y.Qt.`....?|
  #   00035310:  05 5b 91 87 e6 48 48 ee  a3 77 ae ad 5e 2a 56 a2  |.[...HH..w..^*V.|
  #   00035320:  b6 96 86 f3 3c 92 b3 c8  62 4a 6f 96 10 5c 9c bb  |....<...bJo..\..|
  #
  # In the future, we will make the colorization more customizable and
  # allow the groupings to be selectable at 2, 4, 8 or 16.
  #
  class HexDump

    # Printable ASCII codes.
    ASCII_PRINTABLE = (33..126)

    #
    def initialize(options={})
      @offset = 0

      options.each do |k,v|
        __send__("#{k}=", v)
      end

      @color = true if color.nil?
    end

    # Use color?
    attr_accessor :color

    # Show index?
    attr_accessor :index

    # Offset byte count.
    attr_accessor :offset

    # Dump data string as colorized hex table.
    #
    # @param data [String]
    #   String to convert to hex and display.
    #
    def dump(data)
      lines             = data.to_s.scan(/.{1,16}/m)
      max_offset        = (offset + data.size) / 256  #16 * 16
      max_offset_width  = max_offset.to_s.size + 1
      max_hex_width     = 49  #3 * 16 + 1

      out = template()
      off = offset()

      if index?
        puts((' ' * max_offset_width) + "    0  1  2  3  4  5  6  7   8  9  A  B  C  D  E  F\n")
      end

      lines.each_with_index do |line, n|
        offset = off + n * 16
        bytes  = line.unpack("C*")
        hex    = bytes.map{ |c| "%0.2x" % c }.insert(8, '').join(' ')

        plain = bytes.map do |c|
          if ASCII_PRINTABLE.include?(c)
            c = c.chr
          else
            color ? Code::WHITE + Code::STRIKE + '.' + Code::CLEAR : '.' 
          end
        end.join('')

        fill = [offset.to_s.rjust(max_offset_width), hex.ljust(max_hex_width), plain]

        puts(out % fill)
      end      
    end

    # Hex dump a random string.
    #
    def dump_random(size=64)
      data = (0..size).map{ rand(255).chr }.join('')
      dump(data)
    end

    #
    def index?
      @index
    end

  private

    # Hex dump line template.
    #
    # @return [String] hex dump line template
    def template
      if color
        Code::CYAN +
        "%s:  " +
        Code::YELLOW +
        "%s " +
        Code::BLUE +
        "|" +
        Code::CLEAR +
        "%s" +
        Code::BLUE +
        "|" +
        Code::CLEAR
      else
        "%s:  %s |%s|"
      end
    end

  end

end
