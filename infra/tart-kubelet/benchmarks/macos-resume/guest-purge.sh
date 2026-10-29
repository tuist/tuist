#!/bin/sh
# Experimental cache reclamation; never kill processes or the simulator.
# The benchmark reports this pre-suspend cost separately from restoration.
set -eu
sudo /usr/sbin/purge
/usr/bin/vm_stat
/usr/sbin/sysctl vm.swapusage
