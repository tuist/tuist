# -*- encoding: utf-8 -*-
# stub: trailblazer-option 0.1.2 ruby lib

Gem::Specification.new do |s|
  s.name = "trailblazer-option".freeze
  s.version = "0.1.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Nick Sutterer".freeze]
  s.date = "2021-11-07"
  s.description = "Wrap an option at compile-time and `call` it at runtime, which allows to have the common `-> ()`, `:method` or `Callable` pattern used for most options.".freeze
  s.email = ["apotonick@gmail.com".freeze]
  s.homepage = "https://trailblazer.to/".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.1.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Callable patterns for options in Trailblazer".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0"])
    s.add_development_dependency(%q<minitest-line>.freeze, ["~> 0.6.5"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
  else
    s.add_dependency(%q<minitest>.freeze, ["~> 5.0"])
    s.add_dependency(%q<minitest-line>.freeze, ["~> 0.6.5"])
    s.add_dependency(%q<rake>.freeze, ["~> 13.0"])
  end
end
