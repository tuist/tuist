# -*- encoding: utf-8 -*-
# stub: cucumber-cucumber-expressions 12.1.3 ruby lib

Gem::Specification.new do |s|
  s.name = "cucumber-cucumber-expressions".freeze
  s.version = "12.1.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/cucumber/cucumber/issues", "changelog_uri" => "https://github.com/cucumber/common/blob/main/cucumber-expressions/CHANGELOG.md", "documentation_uri" => "https://cucumber.io/docs/cucumber/cucumber-expressions/", "mailing_list_uri" => "https://groups.google.com/forum/#!forum/cukes", "source_code_uri" => "https://github.com/cucumber/common/blob/main/cucumber-expressions/ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Aslak Helles\u00F8y".freeze]
  s.date = "2021-09-01"
  s.description = "Cucumber Expressions - a simpler alternative to Regular Expressions".freeze
  s.email = "cukes@googlegroups.com".freeze
  s.homepage = "https://github.com/cucumber/cucumber-expressions-ruby#readme".freeze
  s.licenses = ["MIT".freeze]
  s.rdoc_options = ["--charset=UTF-8".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3".freeze)
  s.rubygems_version = "3.2.32".freeze
  s.summary = "cucumber-expressions-12.1.3".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rake>.freeze, ["~> 13.0", ">= 13.0.6"])
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3.10", ">= 3.10.0"])
  else
    s.add_dependency(%q<rake>.freeze, ["~> 13.0", ">= 13.0.6"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3.10", ">= 3.10.0"])
  end
end
