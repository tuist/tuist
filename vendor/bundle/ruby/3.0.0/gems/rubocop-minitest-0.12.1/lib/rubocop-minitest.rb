# frozen_string_literal: true

require 'rubocop'

require_relative 'rubocop/minitest'
require_relative 'rubocop/minitest/version'
require_relative 'rubocop/minitest/inject'

RuboCop::Minitest::Inject.defaults!

require_relative 'rubocop/cop/minitest_cops'
