"""Read-only Grafana integration check. Run from an authorized tailnet device."""

import datetime
import json
import sys
import urllib.request


base = sys.argv[1].rstrip("/")


def request(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)


user = request("/api/user")
assert not user["isGrafanaAdmin"], "Expected a Viewer, not a Grafana admin"
orgs = request("/api/user/orgs")
assert orgs and all(org["role"] == "Viewer" for org in orgs), "Expected Viewer role only"
for uid in ["greptime-staging-metrics", "greptime-staging-sql"]:
    health = request(f"/api/datasources/uid/{uid}/health")
    assert health["status"] == "OK", f"{uid}: {health.get('message')}"
    print(f"PASS: {uid} authenticated health")

now = datetime.datetime.now(datetime.timezone.utc)
start = now - datetime.timedelta(minutes=15)
dashboard = request("/api/dashboards/uid/greptime-staging")["dashboard"]
for panel in dashboard["panels"]:
    target = dict(panel["targets"][0])
    target["datasource"] = panel["datasource"]
    target["intervalMs"] = 15000
    target["maxDataPoints"] = 100
    if "rawSql" in target:
        # Blank Trace ID means latest in the same bounded window, as in the UI.
        target["rawSql"] = target["rawSql"].replace("${trace_id:sqlstring}", "''")
    result = request("/api/ds/query", {
        "from": str(int(start.timestamp() * 1000)),
        "to": str(int(now.timestamp() * 1000)),
        "queries": [target],
    })["results"][target["refId"]]
    assert not result.get("error"), f"{panel['title']}: {result.get('error')}"
    frames = result.get("frames", [])
    rows = sum(len((frame.get("data", {}).get("values") or [[]])[0]) for frame in frames)
    assert rows > 0, f"{panel['title']}: no actual telemetry in the last 15 minutes"
    if panel["type"] == "traces":
        fields = {field["name"] for frame in frames for field in frame["schema"]["fields"]}
        assert {"traceID", "spanID", "startTime", "duration"} <= fields, fields
    print(f"PASS: {panel['title']} returned {rows} rows across {len(frames)} frames")

print("PASS: metrics, logs, spans and trace waterfall queried through Grafana as Viewer")
