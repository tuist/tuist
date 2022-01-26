# coding: utf-8
lib = File.expand_path("../lib/", __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)
require "thor/version"

Gem::Specification.new do |spec|
  spec.add_development_dependency "bundler", ">= 1.0", "< 3"
  spec.authors = ["Yehuda Katz", "José Valim"]
  spec.description = "Thor is a toolkit for building powerful command-line interfaces."
  spec.email = "ruby-thor@googlegroups.com"
  spec.executables = %w(thor)
  spec.files = %w(.document thor.gemspec) + Dir["*.md", "bin/*", "lib/**/*.rb"]
  spec.homepage = "http://whatisthor.com/"
  spec.licenses = %w(MIT)
  spec.name = "thor"
  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/rails/thor/issues",
    "changelog_uri" => "https://github.com/rails/thor/releases/tag/v#{Thor::VERSION}",
    "documentation_uri" => "http://whatisthor.com/",
    "source_code_uri" => "https://github.com/rails/thor/tree/v#{Thor::VERSION}",
    "wiki_uri" => "https://github.com/rails/thor/wiki",
    "rubygems_mfa_required" => "true",
  }
  spec.require_paths = %w(lib)
  spec.required_ruby_version = ">= 2.0.0"
  spec.required_rubygems_version = ">= 1.3.5"
  spec.summary = spec.description
  spec.version = Thor::VERSION
end
