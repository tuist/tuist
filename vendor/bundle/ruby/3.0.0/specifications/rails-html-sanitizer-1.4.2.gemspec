# -*- encoding: utf-8 -*-
# stub: rails-html-sanitizer 1.4.2 ruby lib

Gem::Specification.new do |s|
  s.name = "rails-html-sanitizer".freeze
  s.version = "1.4.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/rails/rails-html-sanitizer/issues", "changelog_uri" => "https://github.com/rails/rails-html-sanitizer/blob/v1.4.2/CHANGELOG.md", "documentation_uri" => "https://www.rubydoc.info/gems/rails-html-sanitizer/1.4.2", "source_code_uri" => "https://github.com/rails/rails-html-sanitizer/tree/v1.4.2" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Rafael Mendon\u00E7a Fran\u00E7a".freeze, "Kasper Timm Hansen".freeze]
  s.date = "2021-08-24"
  s.description = "HTML sanitization for Rails applications".freeze
  s.email = ["rafaelmfranca@gmail.com".freeze, "kaspth@gmail.com".freeze]
  s.homepage = "https://github.com/rails/rails-html-sanitizer".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "This gem is responsible to sanitize HTML fragments in Rails applications.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<loofah>.freeze, ["~> 2.3"])
    s.add_development_dependency(%q<bundler>.freeze, [">= 1.3"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_development_dependency(%q<rails-dom-testing>.freeze, [">= 0"])
  else
    s.add_dependency(%q<loofah>.freeze, ["~> 2.3"])
    s.add_dependency(%q<bundler>.freeze, [">= 1.3"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_dependency(%q<rails-dom-testing>.freeze, [">= 0"])
  end
end
