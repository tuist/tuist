# -*- encoding: utf-8 -*-
# stub: method_source 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "method_source".freeze
  s.version = "1.0.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["John Mair (banisterfiend)".freeze]
  s.date = "2020-03-19"
  s.description = "retrieve the sourcecode for a method".freeze
  s.email = "jrmair@gmail.com".freeze
  s.homepage = "http://banisterfiend.wordpress.com".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "retrieve the sourcecode for a method".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3.6"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 0.9"])
  else
    s.add_dependency(%q<rspec>.freeze, ["~> 3.6"])
    s.add_dependency(%q<rake>.freeze, ["~> 0.9"])
  end
end
