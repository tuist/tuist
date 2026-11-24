#!/usr/bin/env python3
"""Check the runner VM host-OOM rule against real and look-alike kernel lines."""

import json
from pathlib import Path
import re

DIRECTORY = Path(__file__).resolve().parent
[rule] = json.loads((DIRECTORY / "runner-vm-oom-alert-rules.json").read_text())
query = next(item for item in rule["data"] if item["refId"] == "A")
condition = next(item["model"] for item in rule["data"] if item["refId"] == "C")
assert query["datasourceUid"] == "pulse-sql" and query["model"]["format"] == "table"
assert rule["condition"] == "C" and rule["for"] == "0s" and rule["noDataState"] == "OK"
assert condition["expression"] == "A"
assert condition["conditions"][0]["evaluator"] == {"params": [0], "type": "gt"}
sql = query["model"]["rawSql"]
assert "'tuist-production'" in sql and "'integrations/kubernetes/journal'" in sql
assert "now() - INTERVAL '10 minutes'" in sql and "AS value" in sql


def like(pattern):
    parts = re.split(r"(%|_)", pattern)
    return re.compile("".join(".*" if p == "%" else "." if p == "_" else re.escape(p) for p in parts), re.S)


patterns = [like(p) for p in re.findall(r"body LIKE '([^']*)'", sql)]
assert len(patterns) == 2


def matches(line):
    return all(p.fullmatch(line) for p in patterns)


# The host kill from 2026-11-17 on qr9fz-ppx6x, and the 8 GiB shape's.
assert matches("Memory cgroup out of memory: Killed process 2713474 (qemu-system-x86) total-vm:37427172kB, anon-rss:22760kB, file-rss:85504kB, shmem-rss:35046400kB, UID:0 pgtables:69564kB oom_score_adj:-999")
assert matches("Memory cgroup out of memory: Killed process 2252154 (qemu-system-x86) total-vm:11224952kB, anon-rss:17988kB, file-rss:87040kB, shmem-rss:10465280kB, UID:0 pgtables:21376kB oom_score_adj:-999")
# Other memcg kills on runner hosts (Kura, Firecracker sandboxes) are not runner VMs.
assert not matches("Memory cgroup out of memory: Killed process 991 (kura) total-vm:1kB, anon-rss:1kB, file-rss:0kB, shmem-rss:0kB")
assert not matches("Memory cgroup out of memory: Killed process 992 (firecracker) total-vm:1kB, anon-rss:1kB, file-rss:0kB, shmem-rss:0kB")
# The oom-kill summary line names the task but is not the kill record itself.
assert not matches("oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=/,task=qemu-system-x86,pid=2713474,uid=0")
# A guest-side kill (the job's own container) is expected behavior, not this alert.
assert not matches("Out of memory: Killed process 4242 (java) total-vm:1kB, anon-rss:1kB, file-rss:0kB, shmem-rss:0kB")
print("Runner VM host-OOM rule matches QEMU memcg kills only.")
