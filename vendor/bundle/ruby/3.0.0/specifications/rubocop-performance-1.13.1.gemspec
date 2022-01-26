# -*- encoding: utf-8 -*-
# stub: rubocop-performance 1.13.1 ruby lib

Gem::Specification.new do |s|
  s.name = "rubocop-performance".freeze
  s.version = "1.13.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/rubocop/rubocop-performance/issues", "changelog_uri" => "https://github.com/rubocop/rubocop-performance/blob/master/CHANGELOG.md", "documentation_uri" => "https://docs.rubocop.org/rubocop-performance/1.13/", "homepage_uri" => "https://docs.rubocop.org/rubocop-performance/", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/rubocop/rubocop-performance/" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Bozhidar Batsov".freeze, "Jonas Arvidsson".freeze, "Yuji Nakayama".freeze]
  s.date = "2022-01-01"
  s.description = "A collection of RuboCop cops to check for performance optimizations\nin Ruby code.\n".freeze
  s.email = "rubocop@googlegroups.com".freeze
  s.extra_rdoc_files = ["LICENSE.txt".freeze, "README.md".freeze]
  s.files = ["LICENSE.txt".freeze, "README.md".freeze]
  s.homepage = "https://github.com/rubocop/rubocop-performance".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Automatic performance checking tool for Ruby code.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<rubocop>.freeze, [">= 1.7.0", "< 2.0"])
    s.add_runtime_dependency(%q<rubocop-ast>.freeze, [">= 0.4.0"])
  else
    s.add_dependency(%q<rubocop>.freeze, [">= 1.7.0", "< 2.0"])
    s.add_dependency(%q<rubocop-ast>.freeze, [">= 0.4.0"])
  end
end
