# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))

ENV["TEST"] = "true"

require "cocoapods_interactor"

require "minitest/autorun"
require "mocha/minitest"
require "byebug"
require "minitest/reporters"
Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)
