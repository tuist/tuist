# -*- encoding: utf-8 -*-
# stub: cli-ui 1.5.1 ruby lib

Gem::Specification.new do |s|
  s.name = "cli-ui".freeze
  s.version = "1.5.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Burke Libbey".freeze, "Julian Nadeau".freeze, "Lisa Ugray".freeze]
  s.bindir = "exe".freeze
  s.date = "2021-04-15"
  s.description = "Terminal UI framework".freeze
  s.email = ["burke.libbey@shopify.com".freeze, "julian.nadeau@shopify.com".freeze, "lisa.ugray@shopify.com".freeze]
  s.homepage = "https://github.com/shopify/cli-ui".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Terminal UI framework".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0"])
  else
    s.add_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.0"])
  end
end
