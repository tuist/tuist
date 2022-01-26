# -*- encoding: utf-8 -*-
# stub: os 1.1.4 ruby lib

Gem::Specification.new do |s|
  s.name = "os".freeze
  s.version = "1.1.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["rdp".freeze, "David McCullars".freeze]
  s.date = "2021-11-07"
  s.description = "The OS gem allows for some useful and easy functions, like OS.windows? (=> true or false) OS.bits ( => 32 or 64) etc\"".freeze
  s.email = "rogerpack2005@gmail.com".freeze
  s.extra_rdoc_files = ["ChangeLog".freeze, "LICENSE".freeze, "README.md".freeze]
  s.files = ["ChangeLog".freeze, "LICENSE".freeze, "README.md".freeze]
  s.homepage = "http://github.com/rdp/os".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Simple and easy way to know if you're on windows or not (reliably), as well as how many bits the OS is, etc.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rake>.freeze, ["~> 0.8"])
    s.add_development_dependency(%q<test-unit>.freeze, ["~> 3"])
    s.add_development_dependency(%q<rspec>.freeze, [">= 2.0"])
  else
    s.add_dependency(%q<rake>.freeze, ["~> 0.8"])
    s.add_dependency(%q<test-unit>.freeze, ["~> 3"])
    s.add_dependency(%q<rspec>.freeze, [">= 2.0"])
  end
end
