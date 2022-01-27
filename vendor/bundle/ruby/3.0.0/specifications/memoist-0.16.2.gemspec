# -*- encoding: utf-8 -*-
# stub: memoist 0.16.2 ruby lib

Gem::Specification.new do |s|
  s.name = "memoist".freeze
  s.version = "0.16.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Joshua Peek".freeze, "Tarmo T\u00E4nav".freeze, "Jeremy Kemper".freeze, "Eugene Pimenov".freeze, "Xavier Noria".freeze, "Niels Ganser".freeze, "Carl Lerche & Yehuda Katz".freeze, "jeem".freeze, "Jay Pignata".freeze, "Damien Mathieu".freeze, "Jos\u00E9 Valim".freeze, "Matthew Rudy Jacobs".freeze]
  s.date = "2019-12-04"
  s.email = ["josh@joshpeek.com".freeze, "tarmo@itech.ee".freeze, "jeremy@bitsweat.net".freeze, "libc@mac.com".freeze, "fxn@hashref.com".freeze, "niels@herimedia.co".freeze, "wycats@gmail.com".freeze, "jeem@hughesorama.com".freeze, "john.pignata@gmail.com".freeze, "42@dmathieu.com".freeze, "jose.valim@gmail.com".freeze, "matthewrudyjacobs@gmail.com".freeze]
  s.homepage = "https://github.com/matthewrudy/memoist".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.2".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "memoize methods invocation".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<benchmark-ips>.freeze, [">= 0"])
    s.add_development_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.10"])
  else
    s.add_dependency(%q<benchmark-ips>.freeze, [">= 0"])
    s.add_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.10"])
  end
end
