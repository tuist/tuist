require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/reporters'

Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new(detailed_skip: false)

require_relative 'sample_test'

