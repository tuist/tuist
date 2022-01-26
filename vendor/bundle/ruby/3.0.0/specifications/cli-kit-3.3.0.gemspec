# -*- encoding: utf-8 -*-
# stub: cli-kit 3.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "cli-kit".freeze
  s.version = "3.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Burke Libbey".freeze, "Aaron Olson".freeze, "Lisa Ugray".freeze]
  s.bindir = "exe".freeze
  s.date = "2019-06-13"
  s.description = "Terminal UI framework extensions".freeze
  s.email = ["burke.libbey@shopify.com".freeze, "aaron.olson@shopify.com".freeze, "lisa.ugray@shopify.com".freeze]
  s.executables = ["cli-kit".freeze]
  s.files = ["exe/cli-kit".freeze]
  s.homepage = "https://github.com/shopify/cli-kit".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Terminal UI framework extensions".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<cli-ui>.freeze, [">= 1.1.4"])
    s.add_development_dependency(%q<bundler>.freeze, ["~> 1.15"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 10.0"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0"])
  else
    s.add_dependency(%q<cli-ui>.freeze, [">= 1.1.4"])
    s.add_dependency(%q<bundler>.freeze, ["~> 1.15"])
    s.add_dependency(%q<rake>.freeze, ["~> 10.0"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.0"])
  end
end
