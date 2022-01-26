# -*- encoding: utf-8 -*-
# stub: ansi 1.5.0 ruby lib

Gem::Specification.new do |s|
  s.name = "ansi".freeze
  s.version = "1.5.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Thomas Sawyer".freeze, "Florian Frank".freeze]
  s.date = "2015-01-17"
  s.description = "The ANSI project is a superlative collection of ANSI escape code related libraries eabling ANSI colorization and stylization of console output. Byte for byte ANSI is the best ANSI code library available for the Ruby programming language.".freeze
  s.email = ["transfire@gmail.com".freeze]
  s.extra_rdoc_files = ["LICENSE.txt".freeze, "NOTICE.md".freeze, "README.md".freeze, "HISTORY.md".freeze, "DEMO.md".freeze]
  s.files = ["DEMO.md".freeze, "HISTORY.md".freeze, "LICENSE.txt".freeze, "NOTICE.md".freeze, "README.md".freeze]
  s.homepage = "http://rubyworks.github.com/ansi".freeze
  s.licenses = ["BSD-2-Clause".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "ANSI at your fingertips!".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<mast>.freeze, [">= 0"])
    s.add_development_dependency(%q<indexer>.freeze, [">= 0"])
    s.add_development_dependency(%q<ergo>.freeze, [">= 0"])
    s.add_development_dependency(%q<qed>.freeze, [">= 0"])
    s.add_development_dependency(%q<ae>.freeze, [">= 0"])
    s.add_development_dependency(%q<lemon>.freeze, [">= 0"])
  else
    s.add_dependency(%q<mast>.freeze, [">= 0"])
    s.add_dependency(%q<indexer>.freeze, [">= 0"])
    s.add_dependency(%q<ergo>.freeze, [">= 0"])
    s.add_dependency(%q<qed>.freeze, [">= 0"])
    s.add_dependency(%q<ae>.freeze, [">= 0"])
    s.add_dependency(%q<lemon>.freeze, [">= 0"])
  end
end
