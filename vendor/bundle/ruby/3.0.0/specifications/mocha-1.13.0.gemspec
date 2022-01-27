# -*- encoding: utf-8 -*-
# stub: mocha 1.13.0 ruby lib

Gem::Specification.new do |s|
  s.name = "mocha".freeze
  s.version = "1.13.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["James Mead".freeze]
  s.date = "2021-06-25"
  s.description = "Mocking and stubbing library with JMock/SchMock syntax, which allows mocking and stubbing of methods on real (non-mock) classes.".freeze
  s.email = "mocha-developer@googlegroups.com".freeze
  s.homepage = "https://mocha.jamesmead.org".freeze
  s.licenses = ["MIT".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Mocking and stubbing library".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<introspection>.freeze, ["~> 0.0.1"])
    s.add_development_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_development_dependency(%q<rubocop>.freeze, ["<= 0.58.2"])
  else
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<introspection>.freeze, ["~> 0.0.1"])
    s.add_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_dependency(%q<rubocop>.freeze, ["<= 0.58.2"])
  end
end
