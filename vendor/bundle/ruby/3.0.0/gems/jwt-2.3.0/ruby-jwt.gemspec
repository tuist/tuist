lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'jwt/version'

Gem::Specification.new do |spec|
  spec.name = 'jwt'
  spec.version = JWT.gem_version
  spec.authors = [
    'Tim Rudat'
  ]
  spec.email = 'timrudat@gmail.com'
  spec.summary = 'JSON Web Token implementation in Ruby'
  spec.description = 'A pure ruby implementation of the RFC 7519 OAuth JSON Web Token (JWT) standard.'
  spec.homepage = 'https://github.com/jwt/ruby-jwt'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.1'
  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/jwt/ruby-jwt/issues',
    'changelog_uri'   => "https://github.com/jwt/ruby-jwt/blob/v#{JWT.gem_version}/CHANGELOG.md"
  }

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(spec|gemfiles|coverage|bin)/}) }
  spec.executables = []
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = %w[lib]

  spec.add_development_dependency 'appraisal'
  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'simplecov'
end
