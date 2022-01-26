module Sys
  class Uname
    # The version of the sys-uname gem.
    VERSION = '1.2.2'.freeze
  end

  class Platform
    # The version of the sys-uname gem.
    VERSION = Uname::VERSION
  end
end

if File::ALT_SEPARATOR
  require_relative 'windows/uname'
else
  require_relative 'unix/uname'
end

require_relative 'platform'
