# frozen_string_literal: true

require 'rubocop'

require_relative 'rubocop/rake'
require_relative 'rubocop/rake/version'
require_relative 'rubocop/rake/inject'

RuboCop::Rake::Inject.defaults!

require_relative 'rubocop/cop/rake/helper/class_definition'
require_relative 'rubocop/cop/rake/helper/on_task'
require_relative 'rubocop/cop/rake/helper/task_definition'
require_relative 'rubocop/cop/rake/helper/task_name'
require_relative 'rubocop/cop/rake/helper/on_namespace'
require_relative 'rubocop/cop/rake_cops'
