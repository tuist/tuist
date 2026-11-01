"""Minimal application providers for launcher tests, not native application builds."""

load("@rules_android//android:rules.bzl", "ApkInfo")
# The public provider deliberately has no constructor. This test double uses
# its raw initializer; real consumers receive the provider from rules_apple.
load("@rules_apple//apple/internal:providers.bzl", "new_applebundleinfo")

def _android_impl(ctx):
    payload = ctx.actions.declare_file(ctx.label.name + ".apk")
    ctx.actions.write(payload, "Launcher fixture, not a signed APK")
    return [DefaultInfo(files = depset([payload])), ApkInfo(signed_apk = payload)]

def _apple_impl(ctx):
    payload = ctx.actions.declare_file(ctx.label.name + ".zip")
    ctx.actions.write(payload, "Launcher fixture, not an application archive")
    return [DefaultInfo(files = depset([payload])), new_applebundleinfo(
        archive = payload,
        product_type = "com.apple.product-type.application",
    )]

android_application = rule(implementation = _android_impl)
apple_application = rule(implementation = _apple_impl)
