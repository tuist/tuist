source 'https://rubygems.org'

gemspec

gem 'rake'

group :development do
  gem 'kicker'
  gem 'colored' # for examples
end

group :spec do
  gem 'bacon'
  gem 'json', '< 2'
  gem 'mocha-on-bacon'
  gem 'prettybacon'

  install_if RUBY_VERSION >= '1.9.3' do
    gem 'rubocop'
    gem 'codeclimate-test-reporter', :require => nil
    gem 'simplecov'
  end
end
