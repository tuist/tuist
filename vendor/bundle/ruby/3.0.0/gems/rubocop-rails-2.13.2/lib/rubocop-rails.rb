# frozen_string_literal: true

require 'rubocop'
require 'rack/utils'
require 'active_support/inflector'

require_relative 'rubocop/rails'
require_relative 'rubocop/rails/version'
require_relative 'rubocop/rails/inject'
require_relative 'rubocop/rails/schema_loader'
require_relative 'rubocop/rails/schema_loader/schema'

RuboCop::Rails::Inject.defaults!

require_relative 'rubocop/cop/rails_cops'
