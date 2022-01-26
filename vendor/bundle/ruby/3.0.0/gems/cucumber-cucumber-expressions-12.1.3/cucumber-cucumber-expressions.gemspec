# -*- encoding: utf-8 -*-

version = File.read(File.expand_path("VERSION", __dir__)).strip

Gem::Specification.new do |s|
  s.name        = 'cucumber-cucumber-expressions'
  s.version     = version
  s.authors     = ["Aslak Hellesøy"]
  s.description = 'Cucumber Expressions - a simpler alternative to Regular Expressions'
  s.summary     = "cucumber-expressions-#{s.version}"
  s.email       = 'cukes@googlegroups.com'
  s.homepage    = "https://github.com/cucumber/cucumber-expressions-ruby#readme"
  s.platform    = Gem::Platform::RUBY
  s.license     = "MIT"
  s.required_ruby_version = ">= 2.3"

  s.metadata    = {
                    'bug_tracker_uri'   => 'https://github.com/cucumber/cucumber/issues',
                    'changelog_uri'     => 'https://github.com/cucumber/common/blob/main/cucumber-expressions/CHANGELOG.md',
                    'documentation_uri' => 'https://cucumber.io/docs/cucumber/cucumber-expressions/',
                    'mailing_list_uri'  => 'https://groups.google.com/forum/#!forum/cukes',
                    'source_code_uri'   => 'https://github.com/cucumber/common/blob/main/cucumber-expressions/ruby',
                  }

  s.add_development_dependency 'rake', '~> 13.0', '>= 13.0.6'
  s.add_development_dependency 'rspec', '~> 3.10', '>= 3.10.0'

  s.rubygems_version = ">= 1.6.1"
  s.files            = `git ls-files`.split("\n").reject {|path| path =~ /\.gitignore$/ }
  s.test_files       = `git ls-files -- spec/*`.split("\n")
  s.rdoc_options     = ["--charset=UTF-8"]
  s.require_path     = "lib"
end
