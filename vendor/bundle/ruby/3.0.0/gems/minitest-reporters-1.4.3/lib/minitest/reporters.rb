require 'minitest'

module Minitest
  require "minitest/relative_position"
  require "minitest/extensible_backtrace_filter"

  module Reporters
    require "minitest/reporters/version"

    autoload :ANSI, "minitest/reporters/ansi"
    autoload :BaseReporter, "minitest/reporters/base_reporter"
    autoload :DefaultReporter, "minitest/reporters/default_reporter"
    autoload :SpecReporter, "minitest/reporters/spec_reporter"
    autoload :ProgressReporter, "minitest/reporters/progress_reporter"
    autoload :RubyMateReporter, "minitest/reporters/ruby_mate_reporter"
    autoload :RubyMineReporter, "minitest/reporters/rubymine_reporter"
    autoload :JUnitReporter, "minitest/reporters/junit_reporter"
    autoload :HtmlReporter, "minitest/reporters/html_reporter"
    autoload :MeanTimeReporter, "minitest/reporters/mean_time_reporter"

    class << self
      attr_accessor :reporters
    end

    def self.use!(console_reporters = ProgressReporter.new, env = ENV, backtrace_filter = nil)
      use_runner!(console_reporters, env)
      if backtrace_filter.nil? && !defined?(::Rails)
        backtrace_filter = ExtensibleBacktraceFilter.default_filter
      end
      Minitest.backtrace_filter = backtrace_filter unless backtrace_filter.nil?

      unless defined?(@@loaded)
        use_around_test_hooks!
        use_old_activesupport_fix!
        @@loaded = true
      end
    end

    def self.use_runner!(console_reporters, env)
      self.reporters = choose_reporters(console_reporters, env)
    end

    def self.use_around_test_hooks!
      Minitest::Test.class_eval do
        def run_with_hooks(*args)
          if defined?(Minitest::Reporters) && (reporters = Minitest::Reporters.reporters)
            reporters.each { |r| r.before_test(self) }
            result = run_without_hooks(*args)
            reporters.each { |r| r.after_test(self) }
            result
          else
            run_without_hooks(*args)
          end
        end

        alias_method :run_without_hooks, :run
        alias_method :run, :run_with_hooks
      end
    end

    def self.choose_reporters(console_reporters, env)
      if env["MINITEST_REPORTER"]
        [Minitest::Reporters.const_get(env["MINITEST_REPORTER"]).new]
      elsif env["TM_PID"]
        [RubyMateReporter.new]
      elsif env["RM_INFO"] || env["TEAMCITY_VERSION"]
        [RubyMineReporter.new]
      elsif !env["VIM"]
        Array(console_reporters)
      end
    end

    def self.clock_time
      if minitest_version >= 561
        Minitest.clock_time
      else
        Time.now
      end
    end

    def self.minitest_version
      Minitest::VERSION.delete('.').to_i
    end

    def self.use_old_activesupport_fix!
      if defined?(ActiveSupport::VERSION) && ActiveSupport::VERSION::MAJOR < 4
        require "minitest/old_activesupport_fix"
      end
    end
  end
end
