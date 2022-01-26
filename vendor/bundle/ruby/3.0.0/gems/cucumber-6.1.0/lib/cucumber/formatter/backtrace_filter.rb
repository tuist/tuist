# frozen_string_literal: true

require 'cucumber/platform'

module Cucumber
  module Formatter
    @backtrace_filters = %w[
      /vendor/rails
      lib/cucumber
      bin/cucumber:
      lib/rspec
      gems/
      site_ruby/
      minitest
      test/unit
      .gem/ruby
      bin/bundle
      rdebug-ide
    ]

    @backtrace_filters << RbConfig::CONFIG['rubyarchdir'] if RbConfig::CONFIG['rubyarchdir']
    @backtrace_filters << RbConfig::CONFIG['rubylibdir'] if RbConfig::CONFIG['rubylibdir']

    @backtrace_filters << 'org/jruby/' if ::Cucumber::JRUBY

    BACKTRACE_FILTER_PATTERNS = Regexp.new(@backtrace_filters.join('|'))

    class BacktraceFilter
      def initialize(exception)
        @exception = exception
      end

      def exception
        return @exception if ::Cucumber.use_full_backtrace

        pwd_pattern = /#{::Regexp.escape(::Dir.pwd)}\//m # rubocop:disable Style/RegexpLiteral
        backtrace = @exception.backtrace.map { |line| line.gsub(pwd_pattern, './') }

        filtered = (backtrace || []).reject do |line|
          line =~ BACKTRACE_FILTER_PATTERNS
        end

        if ::ENV['CUCUMBER_TRUNCATE_OUTPUT']
          # Strip off file locations
          filtered = filtered.map do |line|
            line =~ /(.*):in `/ ? Regexp.last_match(1) : line
          end
        end

        @exception.set_backtrace(filtered)
        @exception
      end
    end
  end
end
