# Copyright 2026 Tuist GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Exact count-rollup experiment against a disposable local Pulse instance.

Run with Python 3 and --output /absolute/empty/directory inside Pulse's configured
COPY root (by default data_home/copy). Pulse must listen on loopback port 14000. The harness
creates a uniquely named database; it never connects to a configurable host.
Use --resume after restarting the same instance to verify persisted results
and repeat the final latency comparison in a fresh process.

This is not a production materializer. Immutable ingestion batches and a
manually published frontier model the coverage certificate a production writer
would need. Never add rows to a covered batch. No customer tables are changed.
"""

import argparse
from collections import defaultdict
import csv
import datetime
import hashlib
import http.client
import json
import math
from pathlib import Path
import random
import statistics
import time
import urllib.parse
import uuid

NS = 1_000_000_000
MINUTE = 60 * NS
START = 1_704_067_200 * NS
FINISH = START + 172_800 * NS
LEVELS = ("INFO", "ERROR", "WARN", "info", "FATAL", "warning", None,
          "DEBUG", "error", "WARN", "TRACE")


class Client:
    def __init__(self, database="public"):
        self.database = database
        self.connection = http.client.HTTPConnection("127.0.0.1", 14000, timeout=600)

    def sql(self, query):
        body = urllib.parse.urlencode({"db": self.database, "sql": query})
        started = time.perf_counter_ns()
        self.connection.request("POST", "/v1/sql", body, {
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept-Encoding": "identity",
        })
        response = self.connection.getresponse()
        raw = response.read()
        elapsed = (time.perf_counter_ns() - started) / 1e6
        parsed = json.loads(raw)
        if response.status != 200 or parsed.get("code", 0) != 0:
            raise RuntimeError((query, response.status, parsed))
        return elapsed, parsed


def records(response):
    return response["output"][0]["records"]["rows"]


def cases():
    result = []
    for tenant, label in ((0, "hot"), (3, "small"), (9, "empty")):
        for hours, step in ((1, 60), (6, 60), (24, 240)):
            result.append({"name": f"{label}_{hours}h_periods", "tenant": tenant,
                           "start": FINISH - 2 * hours * 3600 * NS,
                           "finish": FINISH, "step": step})
    result.extend([
        {"name": "unaligned_edges", "tenant": 0, "start": START + 17 * NS + 1,
         "finish": FINISH - 31 * NS - 1, "step": 60},
        {"name": "recent_minute", "tenant": 0, "start": FINISH - 60 * NS,
         "finish": FINISH, "step": 60},
        {"name": "subminute_edges", "tenant": 0, "start": START + 5 * NS,
         "finish": START + 29 * NS, "step": 60},
        {"name": "nonminute_fallback", "tenant": 0, "start": START + 23 * NS,
         "finish": FINISH - 11 * NS, "step": 75},
    ])
    return result


def events(rows, through_batch):
    # Distinct timestamps plus append_mode preserve duplicate event multiplicity.
    for i in range(rows):
        tenant = 0 if i % 4 else i % 7 + 1
        ts = START + (i * 172_680 // rows) * NS
        ts += 0 if i % 11 == 0 else i * 104729 % NS
        yield tenant, 1, ts, LEVELS[i % len(LEVELS)]
    for offset in (0, 1, MINUTE - 1, MINUTE, MINUTE + 1,
                   2 * MINUTE, 2 * MINUTE + 1, 17 * NS + 1):
        yield 0, 1, START + offset, "ERROR"
    if through_batch >= 2:
        for i in range(32768):
            # Most events are recent, but every eighth event is arbitrarily late.
            ts = (START + (i * 7919 % 172_680) * NS if i % 8 == 0 else
                  FINISH - 120 * NS + (i * 120 // 32768) * NS)
            yield 0 if i % 4 else 3, 2, ts + i % 997, LEVELS[i % len(LEVELS)]
        # Exact duplicates in an append-only source must both count.
        yield 0, 2, START + MINUTE, "FATAL"
        yield 0, 2, START + MINUTE, "FATAL"
        for ts in (FINISH - 1, FINISH, FINISH + 1,
                   FINISH - 31 * NS - 2, FINISH - 31 * NS - 1, FINISH - 31 * NS):
            yield 0, 2, ts, "warning"
    if through_batch >= 3:
        for i in range(513):
            yield i % 8, 3, START + (i * 313 % 172_800) * NS + 1, LEVELS[i % len(LEVELS)]


def oracle(rows, through_batch, workloads):
    # Compute bucket membership from event timestamps, not the SQL bucket formula.
    expected = {case["name"]: defaultdict(lambda: [0, 0, 0]) for case in workloads}
    for tenant, _, ts, level in events(rows, through_batch):
        for case in workloads:
            if tenant != case["tenant"] or not case["start"] < ts <= case["finish"]:
                continue
            width = case["step"] * NS
            quotient, remainder = divmod(ts, width)
            bucket = (quotient + bool(remainder)) * case["step"]
            counts = expected[case["name"]][bucket]
            counts[0] += 1
            upper = (level or "").upper()
            counts[1] += upper in ("ERROR", "FATAL")
            counts[2] += upper in ("WARN", "WARNING")
    return {name: [[bucket, *values] for bucket, values in sorted(points.items())]
            for name, points in expected.items()}


def bucket(column, step):
    return f"((arrow_cast({column}, 'Int64') - 1) / {step * NS} + 1) * {step}"


def bounds(column, start, finish):
    # Cast literals, not the time-index column, to preserve storage pruning.
    return (f"{column} > arrow_cast({start}, 'Timestamp(Nanosecond, None)') AND "
            f"{column} <= arrow_cast({finish}, 'Timestamp(Nanosecond, None)')")


COUNTS = ("count(*) AS entries, "
          "count(*) FILTER (WHERE upper(severity_text) IN ('ERROR', 'FATAL')) AS errors, "
          "count(*) FILTER (WHERE upper(severity_text) IN ('WARN', 'WARNING')) AS warnings")


def raw_query(case):
    return (f"SELECT {bucket('timestamp', case['step'])} AS bucket, {COUNTS} "
            f"FROM events WHERE tenant = {case['tenant']} AND "
            f"{bounds('timestamp', case['start'], case['finish'])} "
            "GROUP BY bucket ORDER BY bucket")


def aggregate_query(case, frontier):
    # Only whole minute buckets can be answered by minute summaries. Keep the
    # partially covered first/last minute raw, including nanosecond boundaries.
    left = ((case["start"] + MINUTE - 1) // MINUTE) * MINUTE
    right = case["finish"] // MINUTE * MINUTE
    if case["step"] % 60 or left >= right:
        return raw_query(case)
    tenant = case["tenant"]
    raw_bounds = bounds("timestamp", case["start"], case["finish"])
    branches = [
        f"SELECT {bucket('bucket_end', case['step'])} AS bucket, entries, errors, warnings "
        f"FROM minute_counts WHERE tenant = {tenant} AND batch <= {frontier} "
        f"AND {bounds('bucket_end', left, right)}",
        f"SELECT {bucket('timestamp', case['step'])} AS bucket, {COUNTS} "
        f"FROM events WHERE tenant = {tenant} AND {raw_bounds} "
        f"AND batch > {frontier} GROUP BY bucket",
    ]
    # Separate narrow time ranges let the reader prune boundary scans. Aligned
    # dashboard windows need no covered-batch raw scan at all.
    for start, finish in ((case["start"], left), (right, case["finish"])):
        if start < finish:
            branches.append(
                f"SELECT {bucket('timestamp', case['step'])} AS bucket, {COUNTS} "
                f"FROM events WHERE tenant = {tenant} AND {bounds('timestamp', start, finish)} "
                f"AND batch <= {frontier} GROUP BY bucket")
    return (
        "SELECT bucket, sum(entries) AS entries, sum(errors) AS errors, "
        "sum(warnings) AS warnings FROM (" + " UNION ALL ".join(branches) +
        ") GROUP BY bucket ORDER BY bucket"
    )


def ingest(client, output, rows, batch):
    path = output / f"batch-{batch}.csv"
    count = 0
    null_count = 0
    with path.open("w") as stream:
        writer = csv.writer(stream)
        writer.writerow(("tenant", "batch", "timestamp", "severity_text"))
        for tenant, event_batch, ns, level in events(rows, batch):
            if event_batch != batch:
                continue
            seconds, nanos = divmod(ns, NS)
            timestamp = datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc)
            text = timestamp.strftime("%Y-%m-%dT%H:%M:%S") + f".{nanos:09}Z"
            writer.writerow((tenant, batch, text, level))
            count += 1
            null_count += level is None
    elapsed, _ = client.sql(f"COPY events FROM '{path}' WITH (format='csv')")
    client.sql("ADMIN flush_table('events')")
    actual = records(client.sql(
        "SELECT count(*), count(*) FILTER (WHERE severity_text IS NULL) "
        f"FROM events WHERE batch = {batch}")[1])[0]
    if actual != [count, null_count]:
        raise AssertionError(("ingested counts", batch, actual, [count, null_count]))
    path.unlink()
    return {"batch": batch, "rows": count, "null_severities": null_count, "copy_ms": elapsed}


def materialize(client, batch):
    # Idempotent keys (tenant, batch, bucket_end) replace, rather than increment,
    # each immutable batch's counts. Publishing a frontier is a separate step.
    query = (
        "INSERT INTO minute_counts (tenant, batch, bucket_end, entries, errors, warnings) "
        f"SELECT tenant, batch, arrow_cast(({bucket('timestamp', 60)}) * {NS}, "
        f"'Timestamp(Nanosecond, None)') AS bucket_end, {COUNTS} "
        f"FROM events WHERE batch = {batch} GROUP BY tenant, batch, bucket_end"
    )
    elapsed, _ = client.sql(query)
    client.sql("ADMIN flush_table('minute_counts')")
    return {"batch": batch, "materialize_ms": elapsed, "sql": query}


def verify(client, output, rows, through_batch, frontier, label):
    workloads = cases()
    expected = oracle(rows, through_batch, workloads)
    digests = {}
    for case in workloads:
        for kind, query in (("raw", raw_query(case)),
                            ("aggregate", aggregate_query(case, frontier))):
            response = client.sql(query)[1]
            columns = response["output"][0]["records"]["schema"]["column_schemas"]
            if [(c["name"], c["data_type"]) for c in columns] != [
                    ("bucket", "Int64"), ("entries", "Int64"),
                    ("errors", "Int64"), ("warnings", "Int64")]:
                raise AssertionError((label, case["name"], kind, "wire schema changed", columns))
            actual = records(response)
            if actual != expected[case["name"]]:
                (output / "mismatch.json").write_text(json.dumps({
                    "label": label, "case": case, "kind": kind, "sql": query,
                    "actual": actual, "expected": expected[case["name"]],
                }, indent=2))
                raise AssertionError((label, case["name"], kind, "see mismatch.json"))
        digests[case["name"]] = hashlib.sha256(
            json.dumps(expected[case["name"]]).encode()).hexdigest()
    result = {"stage": label, "through_batch": through_batch, "frontier": frontier,
              "cases": len(workloads), "oracle_digests": digests}
    with (output / "verification.jsonl").open("a") as stream:
        stream.write(json.dumps(result) + "\n")
    print(json.dumps(result), flush=True)
    return expected


def benchmark(client, output, expected, frontier, label, rounds):
    workloads = cases()
    queries = {case["name"]: {"raw": raw_query(case),
                              "aggregate": aggregate_query(case, frontier)}
               for case in workloads}
    (output / f"queries-{label}.json").write_text(json.dumps(queries, indent=2))
    for name, variants in queries.items():
        for variant, query in variants.items():
            plan = client.sql("EXPLAIN ANALYZE " + query)[1]
            (output / f"plan-{label}-{name}-{variant}.json").write_text(json.dumps(plan, indent=2))
            for _ in range(3):
                if records(client.sql(query)[1]) != expected[name]:
                    raise AssertionError((name, variant, "warmup mismatch"))
    with (output / "samples.jsonl").open("a") as stream:
        for iteration in range(rounds):
            order = list(queries)
            random.Random(iteration).shuffle(order)
            for name in order:
                # ABBA then BAAB within each workload; no query-result cache is
                # enabled by the harness. Parsing/oracle checking is not timed.
                variants = ("raw", "aggregate", "aggregate", "raw") if iteration % 2 == 0 else (
                    "aggregate", "raw", "raw", "aggregate")
                for variant in variants:
                    elapsed, response = client.sql(queries[name][variant])
                    if records(response) != expected[name]:
                        raise AssertionError((name, variant, "timed mismatch"))
                    stream.write(json.dumps({"stage": label, "round": iteration,
                                             "case": name, "variant": variant,
                                             "ms": elapsed}) + "\n")
                    stream.flush()
            print(f"{label}: round {iteration + 1}/{rounds}", flush=True)


def summarize(output):
    samples = [json.loads(line) for line in (output / "samples.jsonl").read_text().splitlines()]
    result = []
    for stage in sorted({s["stage"] for s in samples}):
        for case in cases():
            row = {"stage": stage, "case": case["name"]}
            for variant in ("raw", "aggregate"):
                values = sorted(s["ms"] for s in samples if s["stage"] == stage and
                                s["case"] == case["name"] and s["variant"] == variant)
                row[variant] = {"p50_ms": statistics.median(values),
                                "p95_ms": values[math.ceil(len(values) * .95) - 1],
                                "samples": len(values)}
            row["p50_speedup"] = row["raw"]["p50_ms"] / row["aggregate"]["p50_ms"]
            result.append(row)
    (output / "summary.json").write_text(json.dumps(result, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rows", type=int, default=2_000_000)
    parser.add_argument("--rounds", type=int, default=15)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    output = args.output.resolve()
    if "'" in str(output) or args.rows < 1 or args.rounds < 1:
        parser.error("output cannot contain quotes; rows and rounds must be positive")
    if args.resume:
        manifest = json.loads((output / "manifest.json").read_text())
        client = Client(manifest["database"])
        expected = verify(client, output, manifest["rows"], 3, 2, "restart")
        benchmark(client, output, expected, 2, "restart", args.rounds)
        summarize(output)
        return
    output.mkdir(parents=True, exist_ok=True)
    if list(output.iterdir()):
        parser.error("output directory must be empty for a new run")
    database = "pulse_count_bench_" + uuid.uuid4().hex
    Client().sql(f"CREATE DATABASE {database}")
    client = Client(database)
    manifest = {"database": database, "rows": args.rows, "frontier": 0,
                "prototype": "immutable ingestion batches; manually published coverage",
                "protocol": "warm sequential loopback HTTP; full read; parsing excluded",
                "ingest": [], "materialize": []}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    client.sql('CREATE TABLE events (tenant INT, batch BIGINT, "timestamp" TIMESTAMP(9) TIME INDEX, '
               "severity_text STRING, PRIMARY KEY (tenant, batch)) "
               "ENGINE=mito WITH ('append_mode'='true')")
    client.sql("CREATE TABLE minute_counts (tenant INT, batch BIGINT, "
               # Match COUNT's signed type; mixing signed/unsigned in UNION
               # widens to Decimal and changes the JSON counts to strings.
               "bucket_end TIMESTAMP(9) TIME INDEX, entries BIGINT, "
               "errors BIGINT, warnings BIGINT, "
               "PRIMARY KEY (tenant, batch)) ENGINE=mito")
    manifest["ingest"].append(ingest(client, output, args.rows, 1))
    verify(client, output, args.rows, 1, 0, "no_coverage")
    manifest["materialize"].append(materialize(client, 1))
    verify(client, output, args.rows, 1, 0, "summary_unpublished")
    verify(client, output, args.rows, 1, 1, "first_publish")
    manifest["ingest"].append(ingest(client, output, args.rows, 2))
    expected = verify(client, output, args.rows, 2, 1, "late_raw_tail")
    benchmark(client, output, expected, 1, "late_raw_tail", args.rounds)
    manifest["materialize"].append(materialize(client, 2))
    verify(client, output, args.rows, 2, 1, "second_summary_unpublished")
    verify(client, output, args.rows, 2, 2, "second_publish")
    # Rebuilding an already published immutable batch must not double counts.
    manifest["materialize"].append(materialize(client, 2))
    verify(client, output, args.rows, 2, 2, "idempotent_rebuild")
    manifest["ingest"].append(ingest(client, output, args.rows, 3))
    expected = verify(client, output, args.rows, 3, 2, "late_after_publish")
    benchmark(client, output, expected, 2, "late_after_publish", args.rounds)
    manifest["frontier"] = 2
    for table in ("events", "minute_counts"):
        manifest[table + "_rows"] = records(client.sql(f"SELECT count(*) FROM {table}")[1])[0][0]
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
    summarize(output)
    print(json.dumps(manifest, indent=2), flush=True)


if __name__ == "__main__":
    main()
