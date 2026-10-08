# Hosted tests with native dynamic package products

This fixture exercises a macOS host application and its hosted unit tests using
native Xcode Swift Package integration. All packages are local; no downloads are
needed.

It combines:

- An explicitly dynamic product, reached directly and through a static feature.
- An explicitly static product shared by the host and tests.
- An automatic product shared by the host and tests that remains statically linked.
- Another automatic product with dynamic hints, exercising Xcode's diamond promotion.
- A test-only product.
- Package product names that differ from their Swift module names.
- The Objective-C `-ObjC` linker flag.

The tests call the dynamic module directly and verify that the app and tests see
identical singleton instances from the dynamic, static, automatic-static, and
promoted-automatic modules.
This catches duplicate static runtime state, not merely a successful build.

## Dynamic-linkage hints

Native package references are opaque to Tuist. Use `.runtimeDynamic` when a
product is known to link dynamically, or `.runtimeDynamicEmbedded` when it must
also be explicitly embedded:

```swift
.package(product: "DynamicProduct", type: .runtimeDynamic)
.package(product: "DynamicProduct", type: .runtimeDynamicEmbedded)
```

These hints preserve the product's link reference in hosted tests. They do not
change the library type in `Package.swift` or force Xcode to build an automatic
product dynamically. Do not apply them to a product that actually builds
statically. In a declaration shared by static feature targets, the hint propagates
to their final linking consumers.

Existing `.runtime` and `.runtimeEmbedded` declarations retain their behavior.
The new enum cases require updates to helper code that switches exhaustively over
native package types.

Embedding alone does not establish dynamic linkage. Use `.runtimeDynamicEmbedded`
on the host when an explicitly dynamic product needs embedding. `.runtimeDynamic`
alone retains the link, not an explicit embed.

Tuist omits a test's explicit embed when the host embeds that product under the
same platform condition. The existing exact-condition comparison is unchanged.
Xcode may synthesize additional embedding for automatic products promoted to
dynamic linkage. The fixture tests shared runtime identity in that case too.

## Run

Using a Tuist binary built from this checkout:

```sh
tuist generate --path examples/xcode/generated_app_with_native_dynamic_package_hosted_tests --no-open
xcodebuild test \
  -workspace examples/xcode/generated_app_with_native_dynamic_package_hosted_tests/HostedPackages.xcworkspace \
  -scheme HostApp -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```
