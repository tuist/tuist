require 'ansi/terminal'

module ANSI

  #
  class Columns

    # Create a column-based layout.
    #
    # @param [String,Array] list
    #   Multiline String or Array of strings to columnize.
    #
    # @param [Hash] options
    #   Options to customize columnization.
    #
    # @option options [Fixnum] :columns
    #   Number of columns.
    #
    # @option options [Symbol] :align
    #   Column alignment, either :left, :right or :center.
    #
    # @option options [String,Fixnum] :padding
    #   String or number or spaces to append to each column.
    #
    # The +format+ block MUST return ANSI codes.
    def initialize(list, options={}, &format)
      self.list = list

      self.columns = options[:columns] || options[:cols]
      self.padding = options[:padding] || 1
      self.align   = options[:align]   || :left
      #self.ansi    = options[:ansi]
      self.format  = format

      #@columns = nil if @columns == 0
    end

    #
    def inspect
      "#<#{self.class}:#{object_id} #{list.inspect} x #{columns}>"
    end

    # List layout into columns. Each new line is taken to be 
    # a row-column cell.
    attr :list

    def list=(list)
      case list
      when ::String
        @list = list.lines.to_a.map{ |e| e.chomp("\n") }
      when ::Array
        @list = list.map{ |e| e.to_s }
      end
    end

    # Default number of columns to display. If nil then the number
    # of coumns is estimated from the size of the terminal.
    attr :columns

    # Set column count ensuring value is either an integer or nil.
    # The the value given is zero, it will be taken to mean the same
    # as nil, which means fit-to-screen.
    def columns=(integer)
      integer = integer.to_i
      @columns = (integer.zero? ? nil : integer)
    end

    # Padding size to apply to cells.
    attr :padding

    # Set padding to string or number (of spaces).
    def padding=(pad)
      case pad
      when Numeric
        @padding = ' ' * pad.to_i
      else
        @padding = pad.to_s
      end
    end

    # Alignment to apply to cells.
    attr :align

    # Set alignment ensuring value is a symbol.
    #
    # @param [#to_sym] symbol
    #   Either `:right`, `:left` or `:center`.
    #
    # @return [Symbol] The given symbol.
    def align=(symbol)
      symbol = symbol.to_sym
      raise ArgumentError, "invalid alignment -- #{symbol.inspect}" \
            unless [:left, :right, :center].include?(symbol)
      @align = symbol
    end

    # Formating to apply to cells.
    attr :format

    # Set formatting procedure. The procedure must return
    # ANSI codes, suitable for passing to String#ansi method.
    def format=(procedure)
      @format = procedure ? procedure.to_proc : nil
    end

    # TODO: Should #to_s also take options and formatting block?
    #       Maybe instead have hoin take all these and leave #to_s bare.

    # Return string in column layout. The number of columns is determined
    # by the `columns` property or overriden by +cols+ argument.
    def to_s(cols=nil)
      to_s_columns(cols || columns)
    end

    #
    def join(cols=nil)
      to_s_columns(cols || columns)
    end

  private

    # Layout string lines into columns.
    #
    # @todo Put in empty strings for blank cells.
    # @todo Centering look like it's off by one to the right.
    #
    def to_s_columns(columns=nil)
      lines = list.to_a
      count = lines.size
      max   = lines.map{ |l| l.size }.max

      if columns.nil?
        width = Terminal.terminal_width
        columns = (width / (max + padding.size)).to_i
      end

      rows = []
      mod = (count / columns.to_f).to_i
      mod += 1 if count % columns != 0

      lines.each_with_index do |line, index|
        (rows[index % mod] ||=[]) << line.strip
      end

      pad = padding
      tmp = template(max, pad)
      str = ""
      rows.each_with_index do |row, ri|
        row.each_with_index do |cell, ci|
          ansi_codes = ansi_formatting(cell, ci, ri)
          if ansi_codes.empty?
            str << (tmp % cell)
          else
            str << (tmp % cell).ansi(*ansi_codes)
          end
        end
        str.rstrip!
        str << "\n"
      end
      str
    end

    # Aligns the cell left or right.
    def template(max, pad)
      case align
      when :center, 'center'
        offset = " " * (max / 2)
        "#{offset}%#{max}s#{offset}#{pad}"
      when :right, 'right'
        "%#{max}s#{pad}"
      else
        "%-#{max}s#{pad}"
      end
    end

    # Used to apply ANSI formatting to each cell.
    def ansi_formatting(cell, col, row)
      if @format
        case @format.arity
        when 0
          f = @format[]
        when 1
          f = @format[cell]
        when 2 
          f = @format[col, row]
        else
          f = @format[cell, col, row]
        end
      else
        f = nil
      end
      [f].flatten.compact
    end

  end

end
