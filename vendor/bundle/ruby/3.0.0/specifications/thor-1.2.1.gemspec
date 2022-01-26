# -*- encoding: utf-8 -*-
# stub: thor 1.2.1 ruby lib

Gem::Specification.new do |s|
  s.name = "thor".freeze
  s.version = "1.2.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.3.5".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/rails/thor/issues", "changelog_uri" => "https://github.com/rails/thor/releases/tag/v1.2.1", "documentation_uri" => "http://whatisthor.com/", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/rails/thor/tree/v1.2.1", "wiki_uri" => "https://github.com/rails/thor/wiki" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yehuda Katz".freeze, "Jos\u00E9 Valim".freeze]
  s.date = "2022-01-04"
  s.description = "Thor is a toolkit for building powerful command-line interfaces.".freeze
  s.email = "ruby-thor@googlegroups.com".freeze
  s.executables = ["thor".freeze]
  s.files = ["bin/thor".freeze]
  s.homepage = "http://whatisthor.com/".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Thor is a toolkit for building powerful command-line interfaces.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, [">= 1.0", "< 3"])
  else
    s.add_dependency(%q<bundler>.freeze, [">= 1.0", "< 3"])
  end
end
