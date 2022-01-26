# cucumber-core

[![CircleCI](https://circleci.com/gh/cucumber/cucumber-ruby-core.svg?style=svg)](https://circleci.com/gh/cucumber/cucumber-ruby-core)
[![Code Climate](https://codeclimate.com/github/cucumber/cucumber-ruby-core.svg)](https://codeclimate.com/github/cucumber/cucumber-ruby-core)
[![Coverage Status](https://coveralls.io/repos/cucumber/cucumber-ruby-core/badge.svg?branch=master)](https://coveralls.io/r/cucumber/cucumber-ruby-core?branch=master)
[![pull requests](https://oselvar.com/api/badge?label=pull%20requests&csvUrl=https%3A%2F%2Fraw.githubusercontent.com%2Fcucumber%2Foselvar-github-metrics%2Fmain%2Fdata%2Fcucumber%2Fcucumber-ruby-core%2FpullRequests.csv)](https://oselvar.com/github/cucumber/oselvar-github-metrics/main/cucumber/cucumber-ruby-core)
[![issues](https://oselvar.com/api/badge?label=issues&csvUrl=https%3A%2F%2Fraw.githubusercontent.com%2Fcucumber%2Foselvar-github-metrics%2Fmain%2Fdata%2Fcucumber%2Fcucumber-ruby-core%2Fissues.csv)](https://oselvar.com/github/cucumber/oselvar-github-metrics/main/cucumber/cucumber-ruby-core)

Cucumber Core is the [inner hexagon](http://alistair.cockburn.us/Hexagonal+architecture) for the [Ruby flavour of Cucumber](https://github.com/cucumber/cucumber-ruby).

It contains the core domain logic to execute Cucumber features. It has no user interface, just a Ruby API. If you're interested in how Cucumber works, or in building other tools that work with Gherkin documents, you've come to the right place.

## An overview

The entry-point is a single method on the module [`Cucumber::Core`](Cucumber/Core.html) called [`#execute`](Cucumber/Core.html#execute-instance_method). Here's what it does:

1. Parses the plain-text Gherkin documents into an **AST**
2. Compiles the AST down to **test cases**
3. Passes the test cases through any **filters**
4. Executes the test cases, emitting **events** as it goes

We've introduced a number of concepts here, so let's go through them in detail.

### The AST

The Abstract Syntax Tree or [AST](Cucumber/Core/Ast.html) is an object graph that represents the Gherkin documents you've passed into the core. Things like [Feature](Cucumber/Core/Ast/Feature.html), [Scenario](Cucumber/Core/Ast/Scenario.html) and [ExamplesTable](Cucumber/Core/Ast/ExamplesTable.html).

These are immutable value objects.

### Test cases

Your gherkin might contain scenarios, as well as examples from tables beneath a scenario outline.

Test cases represent the general case of both of these. We compile the AST down to instances of [`Cucumber::Core::Test::Case`](Cucumber/Core/Test/Case.html), each containing a number of instances of [`Cucumber::Core::Test::Step`](Cucumber/Core/Test/Step.html). It's these that are then filtered and executed.

Test cases and their test steps are also immutable value objects.

### Filters

Once we have the test cases, and they've been activated by the mappings, you may want to pass them through a filter or two. Filters can be used to do things like activate, sort, replace or remove some of the test cases or their steps before they're executed.

### Events

Events are how you find out what is happening during your test run. As the test cases and steps are executed, the runner emits events to signal what's going on.

The following events are emitted during a run:

- [`TestCaseStarting`](Cucumber/Core/Events/TestCaseStarting.html)
- [`TestStepStarting`](Cucumber/Core/Events/TestStepStarting.html)
- [`TestStepFinished`](Cucumber/Core/Events/TestStepFinished.html)
- [`TestCaseFinished`](Cucumber/Core/Events/TestCaseFinished.html)

That's probably best illustrated with an example.

## Example

Here's an example of how you might use [`Cucumber::Core#execute`](Cucumber/Core#execute-instance_method)

```ruby
require 'cucumber/core'
require 'cucumber/core/filter'

# This is the most complex part of the example. The filter takes test cases as input,
# activates each step with an action block, then passes a new test case with those activated
# steps in it on to the next filter in the chain.
class ActivateSteps < Cucumber::Core::Filter.new
  def test_case(test_case)
    test_steps = test_case.test_steps.map do |step|
      activate(step)
    end

    test_case.with_steps(test_steps).describe_to(receiver)
  end

  private

  def activate(step)
    case step.text
    when /fail/
      step.with_action { raise Failure }
    when /pass/
      step.with_action {}
    else
      step
    end
  end
end

# Create a Gherkin document to run
feature = Cucumber::Core::Gherkin::Document.new(__FILE__, <<-GHERKIN)
Feature:
  Scenario:
    Given passing
    And failing
    And undefined
GHERKIN

# Create a runner class that uses the Core's DSL
class MyRunner
  include Cucumber::Core
end

# Now execute the feature, using the filter we built, and subscribing to
# an event so we can print the output.
MyRunner.new.execute([feature], [ActivateSteps.new]) do |events|
  events.on(:test_step_finished) do |event|
    test_step, result = event.test_step, event.result
    puts "#{test_step.text} #{result}"
  end
end
```

If you run this little Ruby script, you should see the following output:

```
passing ✓
failing ✗
undefined ?
```

## Copyright

Copyright (c) Cucumber Limited.
