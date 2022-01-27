# -*- encoding: utf-8 -*-
# stub: rubocop-shopify 2.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rubocop-shopify".freeze
  s.version = "2.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.org", "source_code_uri" => "https://github.com/Shopify/ruby-style-guide/tree/v2.3.0" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Shopify Engineering".freeze]
  s.date = "2021-10-05"
  s.description = "Gem containing the rubocop.yml config that corresponds to the implementation of the Shopify's style guide for Ruby.".freeze
  s.email = "gems@shopify.com".freeze
  s.homepage = "https://shopify.github.io/ruby-style-guide/".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.32".freeze
  s.summary = "Shopify's style guide for Ruby.".freeze

  s.installed_by_version = "3.2.32" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<rubocop>.freeze, ["~> 1.22"])
  else
    s.add_dependency(%q<rubocop>.freeze, ["~> 1.22"])
  end
end
