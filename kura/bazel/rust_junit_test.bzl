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

# The wrapper serializes tests (--test-threads=1) so consecutive output
# lines correspond to consecutive per-test wall-clock windows and each case
# gets a real duration in JUnit. That trades the harness's default
# parallelism for the timing signal, so even a "small" suite may need the
# medium (300s) timeout that Bazel's default "small" (60s) does not give.
_MIN_TIMEOUT_ORDER = {"small": 0, "medium": 1, "large": 2, "enormous": 3}

def _effective_size(size):
    if _MIN_TIMEOUT_ORDER.get(size, 0) < _MIN_TIMEOUT_ORDER["medium"]:
        return "medium"
    return size

def rust_junit_test(name, tags = None, size = "medium", **kwargs):
    binary_name = name + ".binary"
    inner_tags = ["manual"] + (tags or [])

    # The underlying rust_test is only ever built, never executed, so its
    # `size` never gates a timeout. The wrapper sh_test carries the real
    # per-test runtime and needs the enlarged budget.
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
        size = _effective_size(size),
    )
