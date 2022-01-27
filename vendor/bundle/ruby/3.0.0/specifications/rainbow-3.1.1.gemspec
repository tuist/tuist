# -*- encoding: utf-8 -*-
# stub: rainbow 3.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "rainbow".freeze
  s.version = "3.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Marcin Kulik".freeze, "Olle Jonsson".freeze]
  s.date = "2022-01-11"
  s.description = "Colorize printed text on ANSI terminals".freeze
  s.email = ["m@ku1ik.com".freeze]
  s.homepage = "https://github.com/sickill/rainbow".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Colorize printed text on ANSI terminals".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, [">= 1.3", "< 3"])
  else
    s.add_dependency(%q<bundler>.freeze, [">= 1.3", "< 3"])
  end
end
