# Middleware User Guide

`middleware` is a library which provides a generalized implementation
of the middleware pattern for Ruby. The middleware pattern is a useful
abstraction tool in various cases, but is specifically useful for splitting
large sequential chunks of logic into small pieces.

## Installing

Middleware is distributed as a RubyGem, so simply gem install:

    gem install middleware

## A Basic Example

Below is a basic example of the library in use. If you don't understand
what middleware is, please read below. This example is simply meant to give
you a quick idea of what the library looks like.

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



## Middleware

### What is it?

Middleware is a reusable chunk of logic that is called to perform some
action. The middleware itself is responsible for calling up the next item
in the middleware chain using a recursive-like call. This allows middleware
to perform logic both _before_ and _after_ something is done.

The canonical middleware example is in web request processing, and middleware
is used heavily by both [Rack](#) and [Rails](#).
In web processing, the first middleware is called with some information about
the web request, such as HTTP headers, request URL, etc. The middleware is
responsible for calling the next middleware, and may modify the request along
the way. When the middlewares begin returning, the state now has the HTTP
response, so that the middlewares can then modify the response.

Cool? Yeah! And this pattern is generally usable in a wide variety of
problems.

### Middleware Classes

One method of creating middleware, and by far the most common, is to define
a class that duck types to the following interface:

    class MiddlewareExample
      def initialize(app); end
      def call(env); end
    end

Therefore, a basic middleware example follows:

    class Trace
      def initialize(app)
        @app = app
      end

      def call(env)
        puts "Trace up"
        @app.call(env)
        puts "Trace down"
      end
    end

A basic description of the two methods that a middleware must implement:

  * **initialize(app)** - This is a constructor. It can take additional arguments
    but the first argument sent will always be the next middleware to call, called
    `app` for historical reasons. This should be stored away for later.

  * **call(env)** - This is what is actually invoked to do work. `env` is just some
    state sent in (defined by the caller, but usually a Hash). This call should also
    call `app.call(env)` at some point to move on.

### Middleware Lambdas

A middleware can also be a simple lambda. The downside of using a lambda is that
it only has access to the state on the initial call, there is no "post" step for
lambdas. A basic example, in the context of a web request:

    lambda { |env| puts "You requested: #{env["http.request_url"]}" }

## Middleware Stacks

Middlewares on their own are useful as small chunks of logic, but their real
power comes from building them up into a _stack_. A stack of middlewares are
executed in the order given.

### Basic Building and Running

The middleware library comes with a `Builder` class which provides a nice DSL
for building a stack of middlewares:

    stack = Middleware::Builder.new do
      use Trace
      use lambda { |env| puts "LAMBDA!" }
    end

This `stack` variable itself is now a valid middleware and has the same interface,
so to execute the stack, just call `call` on it:

    stack.call

The call method takes an optional parameter which is the state to pass into the
initial middleware.

### Manipulating a Stack

Stacks also provide a set of methods for manipulating the middleware stack. This
lets you insert, replace, and delete middleware after a stack has already been
created. Given the `stack` variable created above, we can manipulate it as
follows. Please imagine that each example runs with the original `stack` variable,
so that the order of the examples doesn't actually matter:

    # Insert a new item after the Trace middleware
    stack.insert_after(Trace, SomeOtherMiddleware)

    # Replace the lambda
    stack.replace(1, SomeOtherMiddleware)

    # Delete the lambda
    stack.delete(1)

### Passing Additional Constructor Arguments

When using middleware in a stack, you can also pass in additional constructor
arguments. Given the following middleware:

    class Echo
      def initialize(app, message)
        @app = app
        @message = message
      end

      def call(env)
        puts @message
        @app.call(env)
      end
    end

We can initialize `Echo` with a proper message as follows:

    Middleware::Builder.new do
      use Echo, "Hello, World!"
    end

Then when the stack is called, it will output "Hello, World!"

Note that you can also pass blocks in using the `use` method.
