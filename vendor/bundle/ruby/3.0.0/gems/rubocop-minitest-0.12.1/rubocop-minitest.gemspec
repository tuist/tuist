# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rubocop/minitest/version'

Gem::Specification.new do |spec|
  spec.name = 'rubocop-minitest'
  spec.version = RuboCop::Minitest::Version::STRING
  spec.authors = ['Bozhidar Batsov', 'Jonas Arvidsson', 'Koichi ITO']

  spec.summary = 'Automatic Minitest code style checking tool.'
  spec.description = <<~DESCRIPTION
    Automatic Minitest code style checking tool.
    A RuboCop extension focused on enforcing Minitest best practices and coding conventions.
  DESCRIPTION
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 2.5.0'
  spec.metadata = {
    'homepage_uri' => 'https://docs.rubocop.org/rubocop-minitest/',
    'changelog_uri' => 'https://github.com/rubocop/rubocop-minitest/blob/master/CHANGELOG.md',
    'source_code_uri' => 'https://github.com/rubocop/rubocop-minitest',
    'documentation_uri' => "https://docs.rubocop.org/rubocop-minitest/#{RuboCop::Minitest::Version.document_version}",
    'bug_tracker_uri' => 'https://github.com/rubocop/rubocop-minitest/issues'
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'rubocop', '>= 0.90', '< 2.0'
  spec.add_development_dependency 'minitest', '~> 5.11'
end
