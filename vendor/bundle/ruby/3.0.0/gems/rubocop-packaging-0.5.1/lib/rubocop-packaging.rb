# frozen_string_literal: true

require "rubocop"

require_relative "rubocop/packaging"
require_relative "rubocop/packaging/version"
require_relative "rubocop/packaging/inject"

RuboCop::Packaging::Inject.defaults!

require_relative "rubocop/cop/packaging_cops"
