# -*- encoding: utf-8 -*-
# stub: mini_portile2 2.7.1 ruby lib

Gem::Specification.new do |s|
  s.name = "mini_portile2".freeze
  s.version = "2.7.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Luis Lavena".freeze, "Mike Dalessio".freeze, "Lars Kanis".freeze]
  s.date = "2021-10-20"
  s.description = "Simplistic port-like solution for developers. It provides a standard and simplified way to compile against dependency libraries without messing up your system.".freeze
  s.email = "mike.dalessio@gmail.com".freeze
  s.homepage = "https://github.com/flavorjones/mini_portile".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Simplistic port-like solution for developers".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, ["~> 2.1"])
    s.add_development_dependency(%q<minitar>.freeze, ["~> 0.7"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.11"])
    s.add_development_dependency(%q<minitest-hooks>.freeze, ["~> 1.5.0"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_development_dependency(%q<webrick>.freeze, ["~> 1.0"])
  else
    s.add_dependency(%q<bundler>.freeze, ["~> 2.1"])
    s.add_dependency(%q<minitar>.freeze, ["~> 0.7"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.11"])
    s.add_dependency(%q<minitest-hooks>.freeze, ["~> 1.5.0"])
    s.add_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_dependency(%q<webrick>.freeze, ["~> 1.0"])
  end
end
