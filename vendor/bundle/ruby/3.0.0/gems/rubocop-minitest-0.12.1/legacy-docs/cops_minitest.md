# Minitest

## Minitest/AssertEmpty

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.2 | -

This cop enforces the test to use `assert_empty`
instead of using `assert(object.empty?)`.

### Examples

```ruby
# bad
assert(object.empty?)
assert(object.empty?, 'message')

# good
assert_empty(object)
assert_empty(object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-empty](https://github.com/rubocop/minitest-style-guide#assert-empty)

## Minitest/AssertEmptyLiteral

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | No | 0.5 | -

This cop enforces the test to use `assert_empty`
instead of using `assert([], object)`.

### Examples

```ruby
# bad
assert([], object)
assert({}, object)

# good
assert_empty(object)
```

## Minitest/AssertEqual

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.4 | -

This cop enforces the use of `assert_equal(expected, actual)`
over `assert(expected == actual)`.

### Examples

```ruby
# bad
assert("rubocop-minitest" == actual)

# good
assert_equal("rubocop-minitest", actual)
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-equal-arguments-order](https://github.com/rubocop/minitest-style-guide#assert-equal-arguments-order)

## Minitest/AssertIncludes

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.2 | -

This cop enforces the test to use `assert_includes`
instead of using `assert(collection.include?(object))`.

### Examples

```ruby
# bad
assert(collection.include?(object))
assert(collection.include?(object), 'message')

# good
assert_includes(collection, object)
assert_includes(collection, object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-includes](https://github.com/rubocop/minitest-style-guide#assert-includes)

## Minitest/AssertInstanceOf

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.4 | -

This cop enforces the test to use `assert_instance_of(Class, object)`
over `assert(object.instance_of?(Class))`.

### Examples

```ruby
# bad
assert(object.instance_of?(Class))
assert(object.instance_of?(Class), 'message')

# good
assert_instance_of(Class, object)
assert_instance_of(Class, object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-instance-of](https://github.com/rubocop/minitest-style-guide#assert-instance-of)

## Minitest/AssertMatch

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.6 | -

This cop enforces the test to use `assert_match`
instead of using `assert(matcher.match(string))`.

### Examples

```ruby
# bad
assert(matcher.match(string))
assert(matcher.match(string), 'message')

# good
assert_match(regex, string)
assert_match(matcher, string, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-match](https://github.com/rubocop/minitest-style-guide#assert-match)

## Minitest/AssertNil

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.1 | -

This cop enforces the test to use `assert_nil`
instead of using `assert_equal(nil, something)`.

### Examples

```ruby
# bad
assert_equal(nil, actual)
assert_equal(nil, actual, 'message')

# good
assert_nil(actual)
assert_nil(actual, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-nil](https://github.com/rubocop/minitest-style-guide#assert-nil)

## Minitest/AssertRespondTo

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.3 | -

This cop enforces the use of `assert_respond_to(object, :do_something)`
over `assert(object.respond_to?(:do_something))`.

### Examples

```ruby
# bad
assert(object.respond_to?(:do_something))
assert(object.respond_to?(:do_something), 'message')
assert(respond_to?(:do_something))

# good
assert_respond_to(object, :do_something)
assert_respond_to(object, :do_something, 'message')
assert_respond_to(self, :do_something)
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-responds-to-method](https://github.com/rubocop/minitest-style-guide#assert-responds-to-method)

## Minitest/AssertTruthy

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.2 | -

This cop enforces the test to use `assert(actual)`
instead of using `assert_equal(true, actual)`.

### Examples

```ruby
# bad
assert_equal(true, actual)
assert_equal(true, actual, 'message')

# good
assert(actual)
assert(actual, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#assert-truthy](https://github.com/rubocop/minitest-style-guide#assert-truthy)

## Minitest/GlobalExpectations

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.7 | -

This cop checks for deprecated global expectations
and autocorrects them to use expect format.

### Examples

```ruby
# bad
musts.must_equal expected_musts
wonts.wont_match expected_wonts
musts.must_raise TypeError

# good
_(musts).must_equal expected_musts
_(wonts).wont_match expected_wonts
_ { musts }.must_raise TypeError
```

## Minitest/RefuteEmpty

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.3 | -

This cop enforces to use `refute_empty` instead of
using `refute(object.empty?)`.

### Examples

```ruby
# bad
refute(object.empty?)
refute(object.empty?, 'message')

# good
refute_empty(object)
refute_empty(object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-empty](https://github.com/rubocop/minitest-style-guide#refute-empty)

## Minitest/RefuteEqual

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.3 | -

This cop enforces the use of `refute_equal(expected, object)`
over `assert_equal(expected != actual)` or `assert(! expected == actual)`.

### Examples

```ruby
# bad
assert("rubocop-minitest" != actual)
assert(! "rubocop-minitest" == actual)

# good
refute_equal("rubocop-minitest", actual)
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-equal](https://github.com/rubocop/minitest-style-guide#refute-equal)

## Minitest/RefuteFalse

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.3 | -

This cop enforces the use of `refute(object)`
over `assert_equal(false, object)`.

### Examples

```ruby
# bad
assert_equal(false, actual)
assert_equal(false, actual, 'message')

assert(!test)
assert(!test, 'message')

# good
refute(actual)
refute(actual, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-false](https://github.com/rubocop/minitest-style-guide#refute-false)

## Minitest/RefuteIncludes

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.3 | -

This cop enforces the test to use `refute_includes`
instead of using `refute(collection.include?(object))`.

### Examples

```ruby
# bad
refute(collection.include?(object))
refute(collection.include?(object), 'message')

# good
refute_includes(collection, object)
refute_includes(collection, object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-includes](https://github.com/rubocop/minitest-style-guide#refute-includes)

## Minitest/RefuteInstanceOf

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.4 | -

This cop enforces the use of `refute_instance_of(Class, object)`
over `refute(object.instance_of?(Class))`.

### Examples

```ruby
# bad
refute(object.instance_of?(Class))
refute(object.instance_of?(Class), 'message')

# good
refute_instance_of(Class, object)
refute_instance_of(Class, object, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-instance-of](https://github.com/rubocop/minitest-style-guide#refute-instance-of)

## Minitest/RefuteMatch

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.6 | -

This cop enforces the test to use `refute_match`
instead of using `refute(matcher.match(string))`.

### Examples

```ruby
# bad
refute(matcher.match(string))
refute(matcher.match(string), 'message')

# good
refute_match(matcher, string)
refute_match(matcher, string, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-match](https://github.com/rubocop/minitest-style-guide#refute-match)

## Minitest/RefuteNil

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.2 | -

This cop enforces the test to use `refute_nil`
instead of using `refute_equal(nil, something)`.

### Examples

```ruby
# bad
refute_equal(nil, actual)
refute_equal(nil, actual, 'message')

# good
refute_nil(actual)
refute_nil(actual, 'message')
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-nil](https://github.com/rubocop/minitest-style-guide#refute-nil)

## Minitest/RefuteRespondTo

Enabled by default | Safe | Supports autocorrection | VersionAdded | VersionChanged
--- | --- | --- | --- | ---
Enabled | Yes | Yes  | 0.4 | -

This cop enforces the test to use `refute_respond_to(object, :do_something)`
over `refute(object.respond_to?(:do_something))`.

### Examples

```ruby
# bad
refute(object.respond_to?(:do_something))
refute(object.respond_to?(:do_something), 'message')
refute(respond_to?(:do_something))

# good
refute_respond_to(object, :do_something)
refute_respond_to(object, :do_something, 'message')
refute_respond_to(self, :do_something)
```

### References

* [https://github.com/rubocop/minitest-style-guide#refute-respond-to](https://github.com/rubocop/minitest-style-guide#refute-respond-to)
