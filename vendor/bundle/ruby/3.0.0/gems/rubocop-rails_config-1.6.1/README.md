# rubocop-rails_config

[![Gem Version](https://badge.fury.io/rb/rubocop-rails_config.svg)](https://badge.fury.io/rb/rubocop-rails_config)
![Test](https://github.com/toshimaru/rubocop-rails_config/workflows/Test/badge.svg)

RuboCop configuration which has the same code style checking as official Ruby on Rails.

[Official RoR RuboCop Configuration](https://github.com/rails/rails/blob/main/.rubocop.yml)

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem "rubocop-rails_config"
```

## Usage

Add this line to your application's `.rubocop.yml`:

```yml
inherit_gem:
  rubocop-rails_config:
    - config/rails.yml
```

Or just run:

```console
$ rails generate rubocop_rails_config:install
```

## Configuration

### TargetRubyVersion

Although Rails 7 (edge) only supports Ruby 2.7 or more, rubocop-rails_config still supports Ruby 2.5 or more to support as many Ruby versions as possible.

If you'd like to change `TargetRubyVersion`, see [Customization](#customization).

### Rails/AssertNot, Rails/RefuteMethods

| cop | description |
| --- | --- |
| `Rails/AssertNot`     | Prefer assert_not over assert |
| `Rails/RefuteMethods` | Prefer assert_not_x over refute_x |

`assert_not` and `assert_not_xxx` methods are Rails assertion extension, so if you want to use these methods, require `activesupport` gem and inherit `ActiveSupport::TestCase`.

```rb
class AssertNotTest < ActiveSupport::TestCase
  def test_assert_not_method
    assert_not ...(code)...
  end

  def test_assert_not_nil_method
    assert_not_nil ...(code)...
  end
end
```

See also. [ActiveSupport::Testing::Assertions](https://api.rubyonrails.org/classes/ActiveSupport/Testing/Assertions.html)

## Customization

If you'd like to customize the rubocop setting on your project, you can override it.

For example, if you want to change `TargetRubyVersion`, you can do it like:

```yml
# .rubocop.yml
inherit_gem:
  rubocop-rails_config:
    - config/rails.yml

# Override Setting
AllCops:
  TargetRubyVersion: 3.0
```

This overrides `config/rails.yml` setting with `TargetRubyVersion: 3.0`.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
