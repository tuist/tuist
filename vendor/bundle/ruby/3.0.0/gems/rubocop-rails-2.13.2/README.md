# RuboCop Rails

[![Gem Version](https://badge.fury.io/rb/rubocop-rails.svg)](https://badge.fury.io/rb/rubocop-rails)
[![CircleCI](https://circleci.com/gh/rubocop/rubocop-rails.svg?style=svg)](https://circleci.com/gh/rubocop/rubocop-rails)

A [RuboCop](https://github.com/rubocop/rubocop) extension focused on enforcing Rails best practices and coding conventions.

Note: This repository manages rubocop-rails gem (>= 2.0.0). rubocop-rails gem (<= 1.5.0) has been renamed to [rubocop-rails_config](https://rubygems.org/gems/rubocop-rails_config) gem.

## Installation

Just install the `rubocop-rails` gem

```sh
gem install rubocop-rails
```

or if you use bundler put this in your `Gemfile`

```ruby
gem 'rubocop-rails', require: false
```

## Usage

You need to tell RuboCop to load the Rails extension. There are three
ways to do this:

### RuboCop configuration file

Put this into your `.rubocop.yml`.

```yaml
require: rubocop-rails
```

Alternatively, use the following array notation when specifying multiple extensions.

```yaml
require:
  - rubocop-other-extension
  - rubocop-rails
```

Now you can run `rubocop` and it will automatically load the RuboCop Rails
cops together with the standard cops.

### Command line

```sh
rubocop --require rubocop-rails
```

Note: `--rails` option is required while `rubocop` command supports `--rails` option.

### Rake task

```ruby
RuboCop::RakeTask.new do |task|
  task.requires << 'rubocop-rails'
end
```

## The Cops

All cops are located under
[`lib/rubocop/cop/rails`](lib/rubocop/cop/rails), and contain
examples/documentation.

In your `.rubocop.yml`, you may treat the Rails cops just like any other
cop. For example:

```yaml
Rails/FindBy:
  Exclude:
    - lib/example.rb
```

## Documentation

You can read a lot more about RuboCop Rails in its [official docs](https://docs.rubocop.org/rubocop-rails/).

## Compatibility

Rails cops support the following versions:

- Rails 4.2+

## Readme Badge

If you use RuboCop Rails in your project, you can include one of these badges in your readme to let people know that your code is written following the community Rails Style Guide.

[![Rails Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop-rails)

[![Rails Style Guide](https://img.shields.io/badge/code_style-community-brightgreen.svg)](https://rails.rubystyle.guide)

Here are the Markdown snippets for the two badges:

``` markdown
[![Rails Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop-rails)

[![Rails Style Guide](https://img.shields.io/badge/code_style-community-brightgreen.svg)](https://rails.rubystyle.guide)
```

## Contributing

Checkout the [contribution guidelines](CONTRIBUTING.md).

## License

`rubocop-rails` is MIT licensed. [See the accompanying file](LICENSE.txt) for
the full text.
