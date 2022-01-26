# frozen_string_literal: true

require 'cucumber/platform'
require 'cucumber/term/ansicolor'

if Cucumber::WINDOWS_MRI
  unless ENV['ANSICON']
    STDERR.puts %{*** WARNING: You must use ANSICON 1.31 or higher (https://github.com/adoxa/ansicon/) to get coloured output on Windows}
    Cucumber::Term::ANSIColor.coloring = false
  end
end

Cucumber::Term::ANSIColor.coloring = false if !STDOUT.tty? && !ENV.key?('AUTOTEST')

module Cucumber
  module Formatter
    # Defines aliases for coloured output. You don't invoke any methods from this
    # module directly, but you can change the output colours by defining
    # a <tt>CUCUMBER_COLORS</tt> variable in your shell, very much like how you can
    # tweak the familiar POSIX command <tt>ls</tt> with
    # <a href="http://mipsisrisc.com/rambling/2008/06/27/lscolorsls_colors-now-with-linux-support/">$LSCOLORS/$LS_COLORS</a>
    #
    # The colours that you can change are:
    #
    # * <tt>undefined</tt>     - defaults to <tt>yellow</tt>
    # * <tt>pending</tt>       - defaults to <tt>yellow</tt>
    # * <tt>pending_param</tt> - defaults to <tt>yellow,bold</tt>
    # * <tt>failed</tt>        - defaults to <tt>red</tt>
    # * <tt>failed_param</tt>  - defaults to <tt>red,bold</tt>
    # * <tt>passed</tt>        - defaults to <tt>green</tt>
    # * <tt>passed_param</tt>  - defaults to <tt>green,bold</tt>
    # * <tt>outline</tt>       - defaults to <tt>cyan</tt>
    # * <tt>outline_param</tt> - defaults to <tt>cyan,bold</tt>
    # * <tt>skipped</tt>       - defaults to <tt>cyan</tt>
    # * <tt>skipped_param</tt> - defaults to <tt>cyan,bold</tt>
    # * <tt>comment</tt>       - defaults to <tt>grey</tt>
    # * <tt>tag</tt>           - defaults to <tt>cyan</tt>
    #
    # For instance, if your shell has a black background and a green font (like the
    # "Homebrew" settings for OS X' Terminal.app), you may want to override passed
    # steps to be white instead of green.
    #
    # Although not listed, you can also use <tt>grey</tt>.
    #
    # Examples: (On Windows, use SET instead of export.)
    #
    #   export CUCUMBER_COLORS="passed=white"
    #   export CUCUMBER_COLORS="passed=white,bold:passed_param=white,bold,underline"
    #
    # To see what colours and effects are available, just run this in your shell:
    #
    #   ruby -e "require 'rubygems'; require 'term/ansicolor'; puts Cucumber::Term::ANSIColor.attributes"
    #
    module ANSIColor
      include Cucumber::Term::ANSIColor

      ALIASES = Hash.new do |h, k|
        h[Regexp.last_match(1)] + ',bold' if k.to_s =~ /(.*)_param/
      end.merge(
        'undefined' => 'yellow',
        'pending'   => 'yellow',
        'flaky'     => 'yellow',
        'failed'    => 'red',
        'passed'    => 'green',
        'outline'   => 'cyan',
        'skipped'   => 'cyan',
        'comment'   => 'grey',
        'tag'       => 'cyan'
      )

      if ENV['CUCUMBER_COLORS'] # Example: export CUCUMBER_COLORS="passed=red:failed=yellow"
        ENV['CUCUMBER_COLORS'].split(':').each do |pair|
          a = pair.split('=')
          ALIASES[a[0]] = a[1]
        end
      end

      # Eval to define the color-named methods required by Term::ANSIColor.
      #
      # Examples:
      #
      #   def failed(string=nil, &proc)
      #     red(string, &proc)
      #   end
      #
      #   def failed_param(string=nil, &proc)
      #     red(bold(string, &proc)) + red
      #   end
      ALIASES.each_key do |method_name|
        next if method_name =~ /.*_param/
        code = <<-COLOR
          def #{method_name}(string=nil, &proc)
            #{ALIASES[method_name].split(',').join('(') + '(string, &proc' + ')' * ALIASES[method_name].split(',').length}
          end
          # This resets the colour to the non-param colour
          def #{method_name}_param(string=nil, &proc)
            #{ALIASES[method_name + '_param'].split(',').join('(') + '(string, &proc' + ')' * ALIASES[method_name + '_param'].split(',').length} + #{ALIASES[method_name].split(',').join(' + ')}
          end
        COLOR
        eval(code) # rubocop:disable Security/Eval
      end

      def self.define_grey #:nodoc:
        gem 'genki-ruby-terminfo'
        require 'terminfo'
        case TermInfo.default_object.tigetnum('colors')
        when 0
          raise "Your terminal doesn't support colours."
        when 1
          ::Cucumber::Term::ANSIColor.coloring = false
          alias_method :grey, :white
        when 2..8
          alias_method :grey, :white # rubocop:disable Lint/DuplicateMethods
        else
          define_real_grey
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        if e.class.name == 'TermInfo::TermInfoError'
          STDERR.puts '*** WARNING ***'
          STDERR.puts "You have the genki-ruby-terminfo gem installed, but you haven't set your TERM variable."
          STDERR.puts 'Try setting it to TERM=xterm-256color to get grey colour in output.'
          STDERR.puts "\n"
          alias_method :grey, :white
        else
          define_real_grey
        end
      end

      def self.define_real_grey #:nodoc:
        define_method :grey do |string|
          ::Cucumber::Term::ANSIColor.coloring? ? "\e[90m#{string}\e[0m" : string
        end
      end

      define_grey

      def cukes(n)
        ('(::) ' * n).strip
      end

      def green_cukes(n)
        blink(green(cukes(n)))
      end

      def red_cukes(n)
        blink(red(cukes(n)))
      end

      def yellow_cukes(n)
        blink(yellow(cukes(n)))
      end
    end
  end
end
