# frozen_string_literal: true
# Detect the platform we're running on so we can tweak behaviour
# in various places.
require 'rbconfig'

module Cucumber
  unless defined?(Cucumber::VERSION)
    JRUBY         = defined?(JRUBY_VERSION)
    IRONRUBY      = defined?(RUBY_ENGINE) && RUBY_ENGINE == "ironruby"
    WINDOWS       = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
    OS_X          = RbConfig::CONFIG['host_os'] =~ /darwin/
    WINDOWS_MRI   = WINDOWS && !JRUBY && !IRONRUBY
    RUBY_2_0      = RUBY_VERSION =~ /^2\.0/
    RUBY_1_9      = RUBY_VERSION =~ /^1\.9/
  end
end
