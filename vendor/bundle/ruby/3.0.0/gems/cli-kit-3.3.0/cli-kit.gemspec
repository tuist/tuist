# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cli/kit/version'

Gem::Specification.new do |spec|
  spec.name          = 'cli-kit'
  spec.version       = CLI::Kit::VERSION
  spec.authors       = ['Burke Libbey', 'Aaron Olson', 'Lisa Ugray']
  spec.email         = ['burke.libbey@shopify.com', 'aaron.olson@shopify.com', 'lisa.ugray@shopify.com']

  spec.summary       = 'Terminal UI framework extensions'
  spec.description   = 'Terminal UI framework extensions'
  spec.homepage      = 'https://github.com/shopify/cli-kit'
  spec.license       = 'MIT'

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'cli-ui', '>= 1.1.4'

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
end
