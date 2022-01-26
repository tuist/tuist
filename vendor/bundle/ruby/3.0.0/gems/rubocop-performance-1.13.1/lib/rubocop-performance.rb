# frozen_string_literal: true

require 'rubocop'

require_relative 'rubocop/performance'
require_relative 'rubocop/performance/version'
require_relative 'rubocop/performance/inject'

RuboCop::Performance::Inject.defaults!

require_relative 'rubocop/cop/performance_cops'
