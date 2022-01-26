# Copyright (C) 2009 Thomas Sawyer
#
# This library is based on the original ProgressBar
# by Satoru Takabayashi.
#
# ProgressBar Copyright (C) 2001 Satoru Takabayashi

require 'ansi/code'

module ANSI

  # = Progressbar
  #
  # Progressbar is a text-based progressbar library.
  #
  #   pbar = Progressbar.new( "Demo", 100 )
  #   100.times { pbar.inc }
  #   pbar.finish
  #
  class ProgressBar
    #
    def initialize(title, total, out=STDERR)
      @title = title
      @total = total
      @out   = out

      @bar_length = 80
      @bar_mark = "|"
      @total_overflow = true
      @current = 0
      @previous = 0
      @is_finished = false
      @start_time = Time.now
      @format = "%-14s %3d%% %s %s"
      @format_arguments = [:title, :percentage, :bar, :stat]
      @styles = {}
      #
      yield self if block_given?
      #
      show_progress
    end

    public

    attr_accessor :format
    attr_accessor :format_arguments
    attr_accessor :styles

    #
    def title=(str)
      @title = str
    end
    #
    def bar_mark=(mark)
      @bar_mark = String(mark)[0..0]
    end
    alias_method :barmark=, :bar_mark=
    alias_method :mark=,    :bar_mark=

    def total_overflow=(boolv)
      @total_overflow = boolv ? true : false
    end

    # Get rid of warning about Kenrel method being redefined.
    remove_method :format

    # Set format and format arguments.
    def format(format, *arguments)
      @format = format
      @format_arguments = *arguments unless arguments.empty?
    end

    # Set ANSI styling options.
    def style(options)
      @styles = options
    end

    #
    def standard_mode
      @format = "%-14s %3d%% %s %s"
      @format_arguments = [:title, :percentage, :bar, :stat]
    end

    #
    def transfer_mode
      @format = "%-14s %3d%% %s %s"
      @format_arguments = [:title, :percentage, :bar, :stat_for_file_transfer]
    end

    # For backward compatability
    alias_method :file_transfer_mode, :transfer_mode

    def finish
      @current = @total
      @is_finished = true
      show_progress
    end

    def flush
      @out.flush
    end

    def halt
      @is_finished = true
      show_progress
    end

    def set(count)
      if count < 0
        raise "invalid count less than zero: #{count}"
      elsif count > @total
        if @total_overflow
          @total = count + 1
        else
          raise "invalid count greater than total: #{count}"
        end
      end
      @current = count
      show_progress
      @previous = @current
    end

    #
    def reset
      @current = 0
      @is_finished = false
    end

    #
    def inc(step = 1)
      @current += step
      @current = @total if @current > @total
      show_progress
      @previous = @current
    end

    #
    def clear
      @out.print(" " * get_width + eol)
    end

    def inspect
      "(ProgressBar: #{@current}/#{@total})"
    end

    private

    #
    def convert_bytes(bytes)
      if bytes < 1024
        sprintf("%6dB", bytes)
      elsif bytes < 1024 * 1000 # 1000kb
        sprintf("%5.1fKB", bytes.to_f / 1024)
      elsif bytes < 1024 * 1024 * 1000  # 1000mb
        sprintf("%5.1fMB", bytes.to_f / 1024 / 1024)
      else
        sprintf("%5.1fGB", bytes.to_f / 1024 / 1024 / 1024)
      end
    end
    #
    def transfer_rate
      bytes_per_second = @current.to_f / (Time.now - @start_time)
      sprintf("%s/s", convert_bytes(bytes_per_second))
    end
    #
    def bytes
      convert_bytes(@current)
    end
    #
    def format_time(t)
      t = t.to_i
      sec = t % 60
      min  = (t / 60) % 60
      hour = t / 3600
      sprintf("%02d:%02d:%02d", hour, min, sec);
    end
    #
    # ETA stands for Estimated Time of Arrival.
    def eta
      if @current == 0
        "ETA:  --:--:--"
      else
        elapsed = Time.now - @start_time
        eta = elapsed * @total / @current - elapsed;
        sprintf("ETA:  %s", format_time(eta))
      end
    end
    #
    def elapsed
      elapsed = Time.now - @start_time
      sprintf("Time: %s", format_time(elapsed))
    end
    #
    def stat
      if @is_finished then elapsed else eta end
    end
    #
    def stat_for_file_transfer
      if @is_finished then
        sprintf("%s %s %s", bytes, transfer_rate, elapsed)
      else
        sprintf("%s %s %s", bytes, transfer_rate, eta)
      end
    end
    #
    def eol
      if @is_finished then "\n" else "\r" end
    end
    #
    def bar
      len = percentage * @bar_length / 100
      sprintf("|%s%s|", @bar_mark * len, " " *  (@bar_length - len))
    end
    #
    def percentage
      if @total.zero?
        100
      else
        @current  * 100 / @total
      end
    end
    #
    def title
      @title[0,13] + ":"
    end

    # TODO: Use Terminal.terminal_width instead.
    def get_width
      # FIXME: I don't know how portable it is.
      default_width = 80
      begin
        tiocgwinsz = 0x5413
        data = [0, 0, 0, 0].pack("SSSS")
        if @out.ioctl(tiocgwinsz, data) >= 0 then
          #rows, cols, xpixels, ypixels = data.unpack("SSSS")
          cols = data.unpack("SSSS")[1]
          if cols >= 0 then cols else default_width end
        else
          default_width
        end
      rescue Exception
        default_width
      end
    end

    #
    def show
      arguments = @format_arguments.map do |method|
        colorize(send(method), styles[method])
      end
      line      = sprintf(@format, *arguments)
      width     = get_width
      length    = ANSI::Code.uncolor{line}.length
      if length == width - 1
        @out.print(line + eol)
      elsif length >= width
        @bar_length = [@bar_length - (length - width + 1), 0].max
        @bar_length == 0 ?  @out.print(line + eol) : show
      else #line.length < width - 1
        @bar_length += width - length + 1
        show
      end
    end

    #
    def show_progress
      if @total.zero?
        cur_percentage = 100
        prev_percentage = 0
      else
        cur_percentage  = (@current  * 100 / @total).to_i
        prev_percentage = (@previous * 100 / @total).to_i
      end
      if cur_percentage > prev_percentage || @is_finished
        show
      end
    end

    #
    def colorize(part, style)
      return part unless style
      #[style].flatten.inject(part){ |pt, st| ANSI::Code.ansi(pt, *st) }
      ANSI::Code.ansi(part, *style)
    end

  end

  #
  Progressbar = ProgressBar #:nodoc:

end

