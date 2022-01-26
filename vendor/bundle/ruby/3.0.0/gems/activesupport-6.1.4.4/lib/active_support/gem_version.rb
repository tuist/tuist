# frozen_string_literal: true

module ActiveSupport
  # Returns the version of the currently loaded Active Support as a <tt>Gem::Version</tt>.
  def self.gem_version
    Gem::Version.new VERSION::STRING
  end

  module VERSION
    MAJOR = 6
    MINOR = 1
    TINY  = 4
    PRE   = "4"

    STRING = [MAJOR, MINOR, TINY, PRE].compact.join(".")
  end
end
