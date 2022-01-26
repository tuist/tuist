---
name: Bug Report
about: Report an issue with RuboCop Minitest you've discovered.
---

*Be clear, concise and precise in your description of the problem.
Open an issue with a descriptive title and a summary in grammatically correct,
complete sentences.*

*Use the template below when reporting bugs. Please, make sure that
you're running the latest stable RuboCop and that the problem you're reporting
hasn't been reported (and potentially fixed) already.*

*Before filing the ticket you should replace all text above the horizontal
rule with your own words.*

--------

## Expected behavior

Describe here how you expected RuboCop Minitest to behave in this particular situation.

## Actual behavior

Describe here what actually happened.

## Steps to reproduce the problem

This is extremely important! Providing us with a reliable way to reproduce
a problem will expedite its solution.

## RuboCop version

Include the output of `rubocop -V` or `bundle exec rubocop -V` if using Bundler. Here's an example:
You see extension cop versions (e.g. rubocop-minitest, rubocop-performance, and others) output by rubocop -V,
include them as well. Here's an example:

```
$ [bundle exec] rubocop -V
1.10.0 (using Parser 3.0.0.0, rubocop-ast 1.4.1, running on ruby 3.0.0 x86_64-darwin19)
  - rubocop-minitest 0.10.3
  - rubocop-performance 1.9.2
```
