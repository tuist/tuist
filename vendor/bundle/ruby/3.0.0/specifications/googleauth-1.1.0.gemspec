# -*- encoding: utf-8 -*-
# stub: googleauth 1.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "googleauth".freeze
  s.version = "1.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/googleapis/google-auth-library-ruby/issues", "changelog_uri" => "https://github.com/googleapis/google-auth-library-ruby/blob/main/CHANGELOG.md", "source_code_uri" => "https://github.com/googleapis/google-auth-library-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Tim Emiola".freeze]
  s.date = "2021-10-25"
  s.description = "Implements simple authorization for accessing Google APIs, and provides support for Application Default Credentials.".freeze
  s.email = ["temiola@google.com".freeze]
  s.homepage = "https://github.com/googleapis/google-auth-library-ruby".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Google Auth Library for Ruby".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17.3", "< 2.0"])
    s.add_runtime_dependency(%q<jwt>.freeze, [">= 1.4", "< 3.0"])
    s.add_runtime_dependency(%q<memoist>.freeze, ["~> 0.16"])
    s.add_runtime_dependency(%q<multi_json>.freeze, ["~> 1.11"])
    s.add_runtime_dependency(%q<os>.freeze, [">= 0.9", "< 2.0"])
    s.add_runtime_dependency(%q<signet>.freeze, [">= 0.16", "< 2.a"])
  else
    s.add_dependency(%q<faraday>.freeze, [">= 0.17.3", "< 2.0"])
    s.add_dependency(%q<jwt>.freeze, [">= 1.4", "< 3.0"])
    s.add_dependency(%q<memoist>.freeze, ["~> 0.16"])
    s.add_dependency(%q<multi_json>.freeze, ["~> 1.11"])
    s.add_dependency(%q<os>.freeze, [">= 0.9", "< 2.0"])
    s.add_dependency(%q<signet>.freeze, [">= 0.16", "< 2.a"])
  end
end
