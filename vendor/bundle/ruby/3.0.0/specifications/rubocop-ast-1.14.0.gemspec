# -*- encoding: utf-8 -*-
# stub: rubocop-ast 1.14.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rubocop-ast".freeze
  s.version = "1.14.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/rubocop/rubocop-ast/issues", "changelog_uri" => "https://github.com/rubocop/rubocop-ast/blob/master/CHANGELOG.md", "documentation_uri" => "https://docs.rubocop.org/rubocop-ast/", "homepage_uri" => "https://www.rubocop.org/", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/rubocop/rubocop-ast/" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Bozhidar Batsov".freeze, "Jonas Arvidsson".freeze, "Yuji Nakayama".freeze]
  s.date = "2021-12-02"
  s.description = "    RuboCop's Node and NodePattern classes.\n".freeze
  s.email = "rubocop@googlegroups.com".freeze
  s.extra_rdoc_files = ["LICENSE.txt".freeze, "README.md".freeze]
  s.files = ["LICENSE.txt".freeze, "README.md".freeze]
  s.homepage = "https://github.com/rubocop/rubocop-ast".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "RuboCop tools to deal with Ruby code AST.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<parser>.freeze, [">= 3.0.1.1"])
    s.add_development_dependency(%q<bundler>.freeze, [">= 1.15.0", "< 3.0"])
  else
    s.add_dependency(%q<parser>.freeze, [">= 3.0.1.1"])
    s.add_dependency(%q<bundler>.freeze, [">= 1.15.0", "< 3.0"])
  end
end
