# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.2"

gem "bcrypt", "~> 3.1.7"
gem "bootsnap", ">= 1.4.4", require: false
gem "jbuilder", "~> 2.7"
gem "pg", "~> 1.5.0"
gem "puma", "~> 5.0"
gem "rails", "~> 7.0.0"
gem "redis", "~> 4.0"
gem "sass-rails", ">= 6"
gem "sidekiq", "~> 6.2"
gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]
gem "vite_rails", "~> 3.0.3"
gem "faker", "~> 2.19"
gem "appsignal", "~> 3.4"
gem "aws-sdk-s3", "~> 1.112"
gem "react-rails", "~> 2.6"
gem "webpacker", "~> 5.4"
gem "groupdate", "~> 6.1"

# GraphQL
gem "graphql", "~> 2.0.5"
gem "graphiql-rails", group: :development
gem "graphql-schema_comparator", "~> 1.0"

# Authentication / Authorization
gem "devise", "~> 4.8"
gem "rolify", "~> 6.0"
gem "pundit", "~> 2.1"
gem "omniauth", "~> 2.0"
gem "omniauth-github", "~> 2.0"
gem "omniauth-rails_csrf_protection", "~> 1.0"
gem "rubocop-rails_config", "~> 1.7"

group :development, :test do
  gem "foreman", "~> 0.87.2"
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rubocop", "~> 1.18", require: false
  gem "rubocop-rails", "~> 2.11", require: false
  gem "rubocop-shopify", "~> 2.2", require: false
  gem "bullet", "~> 7.0"
  gem "debug", "~> 1.3"
end

group :development do
  gem "listen", "~> 3.3"
  gem "rack-mini-profiler", "~> 2.0"
  gem "spring"
  gem "web-console", ">= 4.1.0"
end

group :test do
  gem "capybara", ">= 3.26"
  gem "selenium-webdriver"
  gem "webdrivers"
  gem "mocha", "~> 2.1.0"
end
