#!/bin/sh
# Diagnostic output goes to the benchmark log, never its sample stream.
set -eu
/usr/bin/vm_stat
/usr/sbin/sysctl vm.swapusage
