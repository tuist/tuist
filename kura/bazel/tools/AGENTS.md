# Kura test reporting

`rust_libtest_junit.sh` runs the compiled libtest binary with JSON events and
invokes the Rust `rust_libtest_junit` reporter. Keep the public target name as
both suite and classname, terminal case counts, durations, ignored cases and
failure output. Preserve the test process's nonzero exit status; report writer
failures must also fail. No Python dependency is needed.

The reporter's unit target is `//bazel/tools:rust_libtest_junit_test` and uses
itself to generate JUnit. Tests cover foreign/malformed output, terminal events,
XML escaping, empty failures, invalid UTF-8 and I/O failures.

Bazel `--test_filter` is not translated into libtest filters. Pass substrings
with `--test_arg=substring` instead. Keep all arguments after binary/suite/reporter
forwarded unchanged, including `--ignored` for explicit opt-in qualification.
