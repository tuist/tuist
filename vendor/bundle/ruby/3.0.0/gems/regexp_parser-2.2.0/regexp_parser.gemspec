$:.unshift File.join(File.dirname(__FILE__), 'lib')

require 'regexp_parser/version'

Gem::Specification.new do |gem|
  gem.name          = 'regexp_parser'
  gem.version       = ::Regexp::Parser::VERSION

  gem.summary       = "Scanner, lexer, parser for ruby's regular expressions"
  gem.description   = 'A library for tokenizing, lexing, and parsing Ruby regular expressions.'
  gem.homepage      = 'https://github.com/ammar/regexp_parser'

  if gem.respond_to?(:metadata)
    gem.metadata    = { 'issue_tracker' => 'https://github.com/ammar/regexp_parser/issues' }
  end

  gem.authors       = ['Ammar Ali']
  gem.email         = ['ammarabuali@gmail.com']

  gem.license       = 'MIT'

  gem.require_paths = ['lib']

  gem.files         = Dir.glob('{lib,spec}/**/*.rb') +
                      Dir.glob('lib/**/*.rl') +
                      Dir.glob('lib/**/*.yml') +
                      %w(Gemfile Rakefile LICENSE README.md CHANGELOG.md regexp_parser.gemspec)

  gem.test_files    = Dir.glob('spec/**/*.rb')

  gem.rdoc_options  = ["--inline-source", "--charset=UTF-8"]

  gem.platform      = Gem::Platform::RUBY

  gem.required_ruby_version = '>= 2.0.0'
end
