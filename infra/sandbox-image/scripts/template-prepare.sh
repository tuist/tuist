#!/bin/sh
# Run once in the pristine Bazel template, before its memory snapshot. Only
# image-owned toolchain pages are warmed; no action, credentials or CAS inputs
# have reached this guest. Every action still gets a fresh VM and private disks.
set -eu
cat /usr/local/bin/sbx-executor > /dev/null
printf 'int sbx_template_probe(void) { return 0; }\n' |
  cc -x c -c -O2 -o /tmp/sbx-template-probe.o -
rm /tmp/sbx-template-probe.o
