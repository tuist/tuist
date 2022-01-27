# Ansi::Logger
# Copyright (c) 2009 Thomas Sawyer
# Copyright (c) 2005 George Moschovitis

require "logger"
require "time"
require "ansi/code"

# = ANSI::Logger
#
# Extended variation of Ruby's standard Logger library that supports
# color output.
#
#   log = ANSI::Logger.new
#
#   log.formatter do |severity, timestamp, progname, msg|
#     ANSI::Logger::SIMPLE_FORMAT % [severity, msg]
#   end
#
#--
# TODO: What's all this about then?
#
# When using debug level logger messages always append 'if $DBG'
# at the end. This hack is needed because Ruby does not support
# lazy evaluation (lisp macros).
#++
class ANSI::Logger < Logger

  # Some available logging formats.
  SIMPLE_FORMAT   = "%5s: %s\n"
  DETAILED_FORMAT = "%s %5s: %s\n"

  # TODO: Not sure I like this approach.
  class ::Logger #:nodoc:
    class LogDevice #:nodoc:
      attr_writer :ansicolor

      def ansicolor?
        @ansicolor.nil? ? true : @ansicolor
      end
    end
  end

  #
  def ansicolor?
    @logdev.ansicolor?
  end

  #
  def ansicolor=(on)
    @logdev.ansicolor = on
  end

  # Dictate the way in which this logger should format the
  # messages it displays. This method requires a block. The
  # block should return formatted strings given severity,
  # timestamp, progname and msg.
  #
  # === Example
  #
  #   logger = ANSI::Logger.new
  #
  #   logger.formatter do |severity, timestamp, progname, msg|
  #     "#{progname}@#{timestamp} - #{severity}::#{msg}"
  #   end
  #
  def formatter(&block)
    self.formatter = block if block
    super
  end

  def styles(options=nil)
    @styles ||= {
      :info  => [],
      :warn  => [:yellow],
      :debug => [:cyan],
      :error => [:red],
      :fatal => [:bold, :red]
    }
    @styles.merge!(options) if options
    @styles
  end

  #
  def info(progname=nil, &block)
    return unless info?
    @logdev.ansicolor? ? info_with_color{ super } : super
  end

  #
  def warn(progname=nil, &block)
    return unless warn?
    @logdev.ansicolor? ? warn_with_color{ super } : super
  end

  #
  def debug(progname=nil, &block)
    return unless debug?
    @logdev.ansicolor? ? debug_with_color{ super } : super
  end

  #
  def error(progname=nil, &block)
    return unless error?
    @logdev.ansicolor? ? error_with_color{ super } : super
  end

  #
  def fatal(progname=nil, &block)
    return unless error?
    @logdev.ansicolor? ? fatal_with_color{ super } : super
  end

private

  def info_with_color #:yield:
    styles[:info].each{ |s| self << ANSI::Code.send(s) }
    yield
    self << ANSI::Code.clear
  end

  def warn_with_color #:yield:
    styles[:warn].each{ |s| self << ANSI::Code.send(s) }
    yield
    self << ANSI::Code.clear
  end

  def error_with_color #:yield:
    styles[:error].each{ |s| self << ANSI::Code.send(s) }
    yield
    self << ANSI::Code.clear
  end

  def debug_with_color #:yield:
    styles[:debug].each{ |s| self << ANSI::Code.send(s) }
    yield
    self << ANSI::Code.clear
  end

  def fatal_with_color #:yield:
    styles[:fatal].each{ |s| self << ANSI::Code.send(s) }
    yield
    self << ANSI::Code.clear
  end

end


# NOTE: trace is deprecated b/c binding of caller is no longer possible.
=begin
  # Prints a trace message to DEBUGLOG (at debug level).
  # Useful for emitting the value of variables, etc.  Use
  # like this:
  #
  #   x = y = 5
  #   trace 'x'        # -> 'x = 5'
  #   trace 'x ** y'   # -> 'x ** y = 3125'
  #
  # If you have a more complicated value, like an array of
  # hashes, then you'll probably want to use an alternative
  # output format.  For instance:
  #
  #   trace 'value', :yaml
  #
  # Valid output format values (the _style_ parameter) are:
  #
  #   :p :inspect
  #   :pp                     (pretty-print, using 'pp' library)
  #   :s :to_s
  #   :y :yaml :to_yaml       (using the 'yaml' library')
  #
  # The default is <tt>:p</tt>.
  #
  # CREDITS:
  #
  # This code comes straight from the dev-utils Gem.
  # Author: Gavin Sinclair <gsinclair@soyabean.com.au>

  def trace(expr, style=:p)
    unless expr.respond_to? :to_str
      warn "trace: Can't evaluate the given value: #{caller.first}"
    else
      raise "FACETS: binding/or_caller is no longer possible"
      require "facets/core/binding/self/of_caller"

      Binding.of_caller do |b|
        value = b.eval(expr.to_str)
        formatter = TRACE_STYLES[style] || :inspect
        case formatter
        when :pp then require 'pp'
        when :y, :yaml, :to_yaml then require 'yaml'
        end
        value_s = value.send(formatter)
        message = "#{expr} = #{value_s}"
        lines = message.split(/\n/)
        indent = "   "
        debug(lines.shift)
        lines.each do |line|
          debug(indent + line)
        end
      end
    end
  end

  TRACE_STYLES = {}  # :nodoc:
  TRACE_STYLES.update(
    :pp => :pp_s, :s => :to_s, :p => :inspect,
    :y => :to_yaml, :yaml => :to_yaml,
    :inspect => :inspect, :to_yaml => :to_yaml
  )
=end
