# Native multipart admission test

Run the existing multipart ShellSpec against a fresh local Kura process without
Docker. The launcher uses temporary data, no peers or inherited credentials, and
256 MiB of transient headroom. It stops the server and removes its data on exit.

From `kura/`, with Python 3 and ShellSpec installed:

```sh
bazel build //:kura
python3 test/e2e/multipart-admission/run.py bazel-bin/kura
```

Use `--shellspec /path/to/shellspec` if ShellSpec is not on `PATH`.
The test checks automatic session capacity, bounded timeout, queued-start wakeup
on completion, and exact queue/outcome metrics. It uses the same test body as
the Docker suite in `spec/e2e/multipart_admission_spec.sh`.
