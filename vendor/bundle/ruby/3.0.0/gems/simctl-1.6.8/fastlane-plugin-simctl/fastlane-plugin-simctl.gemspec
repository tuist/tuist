# coding: utf-8

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/simctl/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-simctl'
  spec.version       = Fastlane::Simctl::VERSION
  spec.author        = 'Renzo Crisostomo'
  spec.email         = 'renzo.crisostomo@me.com'

  spec.summary       = 'Fastlane plugin to interact with xcrun simctl'
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"] + %w(README.md)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'simctl', '~> 1.6.5'

  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'fastlane', '>= 2.53.1'
end
