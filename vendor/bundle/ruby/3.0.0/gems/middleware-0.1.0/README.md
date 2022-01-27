# Middleware

[![Build Status](https://secure.travis-ci.org/mitchellh/middleware.png?branch=master)](http://travis-ci.org/mitchellh/middleware)

This is a generalized library for using middleware patterns within
your Ruby projects.

To get started, the best place to look is [the user guide](https://github.com/mitchellh/middleware/blob/master/user_guide.md).

## Installation

This project is distributed as a RubyGem:

    $ gem install middleware

## Usage

Once you create a basic middleware, you can use the builder to
have a nice DSL to build middleware stacks. Calling the middleware
is simple, as well.

```ruby
# Basic middleware that just prints the inbound and
# outbound steps.
class Trace
  def initialize(app, value)
    @app   = app
    @value = value
  end

  def call(env)
    puts "--> #{@value}"
    @app.call(env)
    puts "<-- #{@value}"
  end
end

# Build the actual middleware stack which runs a sequence
# of slightly different versions of our middleware.
stack = Middleware::Builder.new do
  use Trace, "A"
  use Trace, "B"
  use Trace, "C"
end

# Run it!
stack.call(nil)
```

And the output:

```
--> A
--> B
--> C
<-- C
<-- B
<-- A
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
