require 'ansi/core'
require 'ansi/terminal'

module ANSI

  class Table

    # The Table class can be used to output nicely formatted
    # tables with division lines and alignment.
    #
    # table - array of array
    #
    # options[:align]   - align :left or :right
    # options[:padding] - space to add to each cell
    # options[:fit]     - fit to screen width
    # options[:border]  - 
    #
    # The +format+ block must return ANSI codes to apply
    # to each cell.
    #
    # Other Implementations:
    #
    # * http://github.com/visionmedia/terminal-table
    # * http://github.com/aptinio/text-table
    #
    # TODO: Support for table headers and footers.
    def initialize(table, options={}, &format)
      @table   = table
      @padding = options[:padding] || 0
      @align   = options[:align]
      @fit     = options[:fit]
      @border  = options[:border]
      #@ansi    = [options[:ansi]].flatten
      @format  = format

      @pad = " " * @padding
    end

    #
    attr_accessor :table

    # Fit to scree width.
    attr_accessor :fit

    #
    attr_accessor :padding

    #
    attr_accessor :align

    #
    attr_accessor :format

    #
    attr_accessor :border

    #
    def to_s #(fit=false)
      #row_count = table.size
      #col_count = table[0].size

      max = max_columns(fit)

      div = dividing_line
      top = div #.gsub('+', ".")
      bot = div #.gsub('+', "'")

      body = []
      table.each_with_index do |row, r|
         body_row = []
         row.each_with_index do |cell, c|
           t = cell_template(max[c])
           s = t % cell.to_s
           body_row << apply_format(s, cell, c, r)
         end
         body << "| " + body_row.join(' | ') + " |"
      end

      if border
        body = body.join("\n#{div}\n")
      else
        body = body.join("\n")
      end

      "#{top}\n#{body}\n#{bot}\n"
    end

  private

    # TODO: look at the lines and figure out how many columns will fit
    def fit_width
      width = Terminal.terminal_width
      ((width.to_f / column_size) - (padding + 3)).to_i
    end

    # Calculate the maximun column sizes.
    #
    # @return [Array] maximum size for each column
    def max_columns(fit=false)
      max = Array.new(column_size, 0)
      table.each do |row|
        row.each_with_index do |col, index|
          col = col.to_s
          col = col.unansi
          if fit
            max[index] = [max[index], col.size, fit_width].max
          else
            max[index] = [max[index], col.size].max
          end
        end
      end
      max
    end

    # Number of columns based on the first row of table.
    #
    # @return [Integer] number of columns
    def column_size
      table.first.size
    end

    #
    def cell_template(max)
      case align
      when :right, 'right'
        "#{@pad}%#{max}s"
      else
        "%-#{max}s#{@pad}"
      end
    end

    # TODO: make more efficient
    def dividing_line
      tmp = max_columns(fit).map{ |m| "%#{m}s" }.join(" | ")
      tmp = "| #{tmp} |"
      lin = (tmp % (['-'] * column_size)).gsub(/[^\|]/, '-').gsub('|', '+')
      lin
    end

    #def dividing_line_top
    #  dividing_line.gsub('+', '.')
    #end

    #def dividing_line_bottom
    #  dividing_line.gsub('+', "'")
    #end

    #
    def apply_format(str, cell, col, row)
      if @format
        str.ansi(*ansi_formating(cell, col, row))
      else
        str
      end 
    end

    #
    def ansi_formating(cell, col, row)
      if @format
        case @format.arity
        when 0
          f = @format[]
        when 1
          f = @format[cell]
        when 2 
          f = @format[row, col]
        else
          f = @format[cell, row, col]
        end
      else
        f = nil
      end
      [f].flatten.compact
    end

  end

end

