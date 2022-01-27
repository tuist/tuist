## 1.4.2 / 2021-08-23

* Slightly improve performance.

  Assuming elements are more common than comments, make one less method call per node.

  *Mike Dalessio*

## 1.4.1 / 2021-08-18

* Fix regression in v1.4.0 that did not pass comment nodes to the scrubber.

  Some scrubbers will want to override the default behavior and allow comments, but v1.4.0 only
  passed through elements to the scrubber's `keep_node?` method.

  This change once again allows the scrubber to make the decision on comment nodes, but still skips
  other non-elements like processing instructions (see #115).

  *Mike Dalessio*

## 1.4.0 / 2021-08-18

* Processing Instructions are no longer allowed by Rails::Html::PermitScrubber

  Previously, a PI with a name (or "target") matching an allowed tag name was not scrubbed. There
  are no known security issues associated with these PIs, but similar to comments it's preferred to
  omit these nodes when possible from sanitized output.

  Fixes #115.

  *Mike Dalessio*

## 1.3.0

* Address deprecations in Loofah 2.3.0.

  *Josh Goodall*

## 1.2.0

* Remove needless `white_list_sanitizer` deprecation.

  By deprecating this, we were forcing Rails 5.2 to be updated or spew
  deprecations that users could do nothing about.

  That's pointless and I'm sorry for adding that!

  Now there's no deprecation warning and Rails 5.2 works out of the box, while
  Rails 6 can use the updated naming.

  *Kasper Timm Hansen*

## 1.1.0

* Add `safe_list_sanitizer` and deprecate `white_list_sanitizer` to be removed
  in 1.2.0. https://github.com/rails/rails-html-sanitizer/pull/87

  *Juanito Fatas*

* Remove `href` from LinkScrubber's `tags` as it's not an element.
  https://github.com/rails/rails-html-sanitizer/pull/92

  *Juanito Fatas*

* Explain that we don't need to bump Loofah here if there's CVEs.
  https://github.com/rails/rails-html-sanitizer/commit/d4d823c617fdd0064956047f7fbf23fff305a69b

  *Kasper Timm Hansen*

## 1.0.1

* Added support for Rails 4.2.0.beta2 and above

## 1.0.0

* First release.
