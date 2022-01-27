# -*- encoding: utf-8 -*-
# stub: down 5.2.4 ruby lib

Gem::Specification.new do |s|
  s.name = "down".freeze
  s.version = "5.2.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Janko Marohni\u0107".freeze]
  s.date = "2021-09-12"
  s.email = ["janko.marohnic@gmail.com".freeze]
  s.homepage = "https://github.com/janko/down".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Robust streaming downloads using Net::HTTP, HTTP.rb or wget.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<addressable>.freeze, ["~> 2.8"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.8"])
    s.add_development_dependency(%q<mocha>.freeze, ["~> 1.5"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<http>.freeze, ["~> 5.0"])
    s.add_development_dependency(%q<posix-spawn>.freeze, [">= 0"])
    s.add_development_dependency(%q<http_parser.rb>.freeze, [">= 0"])
    s.add_development_dependency(%q<docker-api>.freeze, [">= 0"])
    s.add_development_dependency(%q<warning>.freeze, [">= 0"])
  else
    s.add_dependency(%q<addressable>.freeze, ["~> 2.8"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.8"])
    s.add_dependency(%q<mocha>.freeze, ["~> 1.5"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<http>.freeze, ["~> 5.0"])
    s.add_dependency(%q<posix-spawn>.freeze, [">= 0"])
    s.add_dependency(%q<http_parser.rb>.freeze, [">= 0"])
    s.add_dependency(%q<docker-api>.freeze, [">= 0"])
    s.add_dependency(%q<warning>.freeze, [">= 0"])
  end
end
