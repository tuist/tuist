# -*- encoding: utf-8 -*-
# stub: google-apis-core 0.4.1 ruby lib

Gem::Specification.new do |s|
  s.name = "google-apis-core".freeze
  s.version = "0.4.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/googleapis/google-api-ruby-client/issues", "changelog_uri" => "https://github.com/googleapis/google-api-ruby-client/tree/master/google-apis-core/CHANGELOG.md", "documentation_uri" => "https://googleapis.dev/ruby/google-apis-core/v0.4.1", "source_code_uri" => "https://github.com/googleapis/google-api-ruby-client/tree/master/google-apis-core" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Google LLC".freeze]
  s.date = "2021-07-20"
  s.email = "googleapis-packages@google.com".freeze
  s.homepage = "https://github.com/google/google-api-ruby-client".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Common utility and base classes for legacy Google REST clients".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<representable>.freeze, ["~> 3.0"])
    s.add_runtime_dependency(%q<retriable>.freeze, [">= 2.0", "< 4.a"])
    s.add_runtime_dependency(%q<addressable>.freeze, ["~> 2.5", ">= 2.5.1"])
    s.add_runtime_dependency(%q<mini_mime>.freeze, ["~> 1.0"])
    s.add_runtime_dependency(%q<googleauth>.freeze, [">= 0.16.2", "< 2.a"])
    s.add_runtime_dependency(%q<httpclient>.freeze, [">= 2.8.1", "< 3.a"])
    s.add_runtime_dependency(%q<rexml>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<webrick>.freeze, [">= 0"])
  else
    s.add_dependency(%q<representable>.freeze, ["~> 3.0"])
    s.add_dependency(%q<retriable>.freeze, [">= 2.0", "< 4.a"])
    s.add_dependency(%q<addressable>.freeze, ["~> 2.5", ">= 2.5.1"])
    s.add_dependency(%q<mini_mime>.freeze, ["~> 1.0"])
    s.add_dependency(%q<googleauth>.freeze, [">= 0.16.2", "< 2.a"])
    s.add_dependency(%q<httpclient>.freeze, [">= 2.8.1", "< 3.a"])
    s.add_dependency(%q<rexml>.freeze, [">= 0"])
    s.add_dependency(%q<webrick>.freeze, [">= 0"])
  end
end
