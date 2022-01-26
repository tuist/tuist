# ANSI namespace module contains all the ANSI related classes.
module ANSI
end

require 'ansi/version'
require 'ansi/core'
require 'ansi/code'
require 'ansi/bbcode'
require 'ansi/columns'
require 'ansi/diff'
require 'ansi/logger'
require 'ansi/mixin'
require 'ansi/progressbar'
require 'ansi/string'
require 'ansi/table'
require 'ansi/terminal'

# Kernel method
def ansi(string, *codes)
  ANSI::Code.ansi(string, *codes)
end

