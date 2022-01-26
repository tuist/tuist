# -*- encoding: utf-8 -*-
# stub: representable 3.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "representable".freeze
  s.version = "3.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Nick Sutterer".freeze]
  s.date = "2021-04-13"
  s.description = "Renders and parses JSON/XML/YAML documents from and to Ruby objects. Includes plain properties, collections, nesting, coercion and more.".freeze
  s.email = ["apotonick@gmail.com".freeze]
  s.homepage = "https://github.com/trailblazer/representable/".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.4.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Renders and parses JSON/XML/YAML documents from and to Ruby objects. Includes plain properties, collections, nesting, coercion and more.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<uber>.freeze, ["< 0.2.0"])
    s.add_runtime_dependency(%q<declarative>.freeze, ["< 0.1.0"])
    s.add_runtime_dependency(%q<trailblazer-option>.freeze, [">= 0.1.1", "< 0.2.0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<test_xml>.freeze, [">= 0.1.6"])
    s.add_development_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_development_dependency(%q<virtus>.freeze, [">= 0"])
    s.add_development_dependency(%q<dry-types>.freeze, [">= 0"])
    s.add_development_dependency(%q<ruby-prof>.freeze, [">= 0"])
  else
    s.add_dependency(%q<uber>.freeze, ["< 0.2.0"])
    s.add_dependency(%q<declarative>.freeze, ["< 0.1.0"])
    s.add_dependency(%q<trailblazer-option>.freeze, [">= 0.1.1", "< 0.2.0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<test_xml>.freeze, [">= 0.1.6"])
    s.add_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_dependency(%q<virtus>.freeze, [">= 0"])
    s.add_dependency(%q<dry-types>.freeze, [">= 0"])
    s.add_dependency(%q<ruby-prof>.freeze, [">= 0"])
  end
end
