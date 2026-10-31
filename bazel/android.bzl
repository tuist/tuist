"""Publish a rules_android application through Tuist previews."""

load("@rules_android//android:rules.bzl", "ApkInfo")
load("//private:preview.bzl", "preview_executable")

def _android_preview_impl(ctx):
    apk = ctx.attr.app[ApkInfo].signed_apk
    if not apk:
        fail("Tuist previews require a signed APK")
    return preview_executable(ctx, apk, "android", ctx.attr.app.label)

android_preview = rule(
    implementation = _android_preview_impl,
    executable = True,
    attrs = {
        "app": attr.label(mandatory = True, providers = [ApkInfo]),
        "_sources": attr.label(default = Label("//private:sources")),
        "_runtime": attr.label(default = Label("@python_3_12//:py3_runtime"), cfg = "exec"),
    },
    doc = "Build a signed android_binary; publish only when run with --publish.",
)
