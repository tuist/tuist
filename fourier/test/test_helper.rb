# frozen_string_literal: true
addpath = lambda do |p|
  $LOAD_PATH.unshift(p) unless $LOAD_PATH.include?(p)
end
addpath.call(File.expand_path("../lib", __dir__))

require 'cli/ui'
require 'fileutils'
require 'tmpdir'
require 'tempfile'
require 'byebug'

CLI::UI::StdoutRouter.enable

require 'minitest/autorun'
require "minitest/unit"
require 'mocha/minitest'
