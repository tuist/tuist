"""rust_junit_test: rules_rs rust_test that emits per-case JUnit XML.

Standard libtest (what `rust_test` runs) does not write JUnit on stable Rust,
so Bazel falls back to synthesizing a one-case-per-target `test.xml` and
Tuist Test Insights collapses the whole target to a single row. This macro
wraps the compiled libtest binary in a small shell adapter that translates
libtest's text output into the JUnit report Bazel expects at
$XML_OUTPUT_FILE, keeping per-case rows in Tuist without changing test
source or splitting the target.

Usage:

    load("//bazel:rust_junit_test.bzl", "rust_junit_test")

    rust_junit_test(
        name = "kura_lib_test",
        crate = ":kura_lib",
        edition = "2024",
    )

The macro forwards every rust_test attribute onto the inner binary target.
See kura/bazel/tools/rust_libtest_junit.sh for the parser.
"""

load("@rules_rs//rs:rust_test.bzl", "rust_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

def rust_junit_test(name, tags = None, size = "medium", **kwargs):
    binary_name = name + ".binary"
    inner_tags = ["manual"] + (tags or [])

    rust_test(
        name = binary_name,
        tags = inner_tags,
        size = size,
        **kwargs
    )

    sh_test(
        name = name,
        srcs = ["//bazel/tools:rust_libtest_junit.sh"],
        args = ["$(rootpath :" + binary_name + ")"],
        data = [":" + binary_name],
        tags = tags,
        size = size,
    )
