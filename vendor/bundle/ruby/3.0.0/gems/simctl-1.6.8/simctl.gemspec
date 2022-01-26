# -*- encoding: utf-8 -*-

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'simctl/version'

Gem::Specification.new do |s|
  s.name = 'simctl'
  s.version = SimCtl::VERSION
  s.summary = 'Ruby interface to xcrun simctl'
  s.description = 'Ruby interface to xcrun simctl'

  s.authors = ['Johannes Plunien']
  s.email = %w[plu@pqpq.de]
  s.homepage = 'https://github.com/plu/simctl'
  s.licenses = ['MIT']

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_development_dependency 'coveralls'
  s.add_development_dependency 'irb'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rubocop', '=0.49.1'

  s.add_dependency 'CFPropertyList'
  s.add_dependency 'naturally'
end
