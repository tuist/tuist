# -*- encoding: utf-8 -*-
# stub: minitest-reporters 1.5.0 ruby lib

Gem::Specification.new do |s|
  s.name = "minitest-reporters".freeze
  s.version = "1.5.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Alexander Kern".freeze]
  s.date = "2022-01-15"
  s.description = "Death to haphazard monkey-patching! Extend Minitest through simple hooks.".freeze
  s.email = ["alex@kernul.com".freeze]
  s.homepage = "https://github.com/CapnKernul/minitest-reporters".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Create customizable Minitest output formats".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<minitest>.freeze, [">= 5.0"])
    s.add_runtime_dependency(%q<ansi>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<ruby-progressbar>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<builder>.freeze, [">= 0"])
    s.add_development_dependency(%q<maruku>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<rubocop>.freeze, [">= 0"])
  else
    s.add_dependency(%q<minitest>.freeze, [">= 5.0"])
    s.add_dependency(%q<ansi>.freeze, [">= 0"])
    s.add_dependency(%q<ruby-progressbar>.freeze, [">= 0"])
    s.add_dependency(%q<builder>.freeze, [">= 0"])
    s.add_dependency(%q<maruku>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<rubocop>.freeze, [">= 0"])
  end
end
