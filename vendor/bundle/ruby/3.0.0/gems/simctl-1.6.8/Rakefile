#!/usr/bin/env rake
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:rspec)
RuboCop::RakeTask.new

desc 'Default: Execute rubocop + rspec'
task default: %i[rubocop rspec]
