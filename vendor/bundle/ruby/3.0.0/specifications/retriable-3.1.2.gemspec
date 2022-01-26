# -*- encoding: utf-8 -*-
# stub: retriable 3.1.2 ruby lib

Gem::Specification.new do |s|
  s.name = "retriable".freeze
  s.version = "3.1.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jack Chu".freeze]
  s.date = "2018-06-11"
  s.description = "Retriable is a simple DSL to retry failed code blocks with randomized exponential backoff. This is especially useful when interacting external api/services or file system calls.".freeze
  s.email = ["jack@jackchu.com".freeze]
  s.homepage = "http://github.com/kamui/retriable".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Retriable is a simple DSL to retry failed code blocks with randomized exponential backoff".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3"])
    s.add_development_dependency(%q<listen>.freeze, ["~> 3.1"])
  else
    s.add_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3"])
    s.add_dependency(%q<listen>.freeze, ["~> 3.1"])
  end
end
