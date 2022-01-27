# -*- encoding: utf-8 -*-
# stub: loofah 2.13.0 ruby lib

Gem::Specification.new do |s|
  s.name = "loofah".freeze
  s.version = "2.13.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/flavorjones/loofah/issues", "changelog_uri" => "https://github.com/flavorjones/loofah/blob/main/CHANGELOG.md", "documentation_uri" => "https://www.rubydoc.info/gems/loofah/", "homepage_uri" => "https://github.com/flavorjones/loofah", "source_code_uri" => "https://github.com/flavorjones/loofah" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Mike Dalessio".freeze, "Bryan Helmkamp".freeze]
  s.date = "2021-12-10"
  s.description = "Loofah is a general library for manipulating and transforming HTML/XML documents and fragments, built on top of Nokogiri.\n\nLoofah excels at HTML sanitization (XSS prevention). It includes some nice HTML sanitizers, which are based on HTML5lib's safelist, so it most likely won't make your codes less secure. (These statements have not been evaluated by Netexperts.)\n\nActiveRecord extensions for sanitization are available in the [`loofah-activerecord` gem](https://github.com/flavorjones/loofah-activerecord).".freeze
  s.email = ["mike.dalessio@gmail.com".freeze, "bryan@brynary.com".freeze]
  s.homepage = "https://github.com/flavorjones/loofah".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Loofah is a general library for manipulating and transforming HTML/XML documents and fragments, built on top of Nokogiri".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<crass>.freeze, ["~> 1.0.2"])
    s.add_runtime_dependency(%q<nokogiri>.freeze, [">= 1.5.9"])
    s.add_development_dependency(%q<hoe-markdown>.freeze, ["~> 1.3"])
    s.add_development_dependency(%q<json>.freeze, ["~> 2.2"])
    s.add_development_dependency(%q<minitest>.freeze, ["~> 5.14"])
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_development_dependency(%q<rdoc>.freeze, [">= 4.0", "< 7"])
    s.add_development_dependency(%q<rr>.freeze, ["~> 1.2.0"])
    s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.1"])
  else
    s.add_dependency(%q<crass>.freeze, ["~> 1.0.2"])
    s.add_dependency(%q<nokogiri>.freeze, [">= 1.5.9"])
    s.add_dependency(%q<hoe-markdown>.freeze, ["~> 1.3"])
    s.add_dependency(%q<json>.freeze, ["~> 2.2"])
    s.add_dependency(%q<minitest>.freeze, ["~> 5.14"])
    s.add_dependency(%q<rake>.freeze, ["~> 13.0"])
    s.add_dependency(%q<rdoc>.freeze, [">= 4.0", "< 7"])
    s.add_dependency(%q<rr>.freeze, ["~> 1.2.0"])
    s.add_dependency(%q<rubocop>.freeze, ["~> 1.1"])
  end
end
