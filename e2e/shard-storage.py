#!/usr/bin/env python3
"""Staging Tuist API -> presigned S3 multipart -> checksum/Range qualification.

No bucket credentials, flag mutations, cluster operations, or signed-URL logs.
Writes disposable plans/objects; their lifecycle and normal plan retention clean up.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP = urllib.request.build_opener(NoRedirect)
# Staging's edge rejects Python's default user agent before API authentication.
HTTP.addheaders = [("User-Agent", "tuist/shard-storage-e2e")]


def request(url, method="GET", data=None, headers=None):
    # Never include the URL, response body or raw exception in errors.
    try:
        return HTTP.open(urllib.request.Request(url, data=data, headers=headers or {}, method=method), timeout=120)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"{method} failed: HTTP {error.code}") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError(f"{method} transport failed") from None


def api(base, path, data=None):
    headers = {"Authorization": "Bearer " + os.environ["TUIST_TOKEN"]}
    if os.environ.get("TUIST_RUNNER_GRANT"):
        headers["x-tuist-runner-grant"] = os.environ["TUIST_RUNNER_GRANT"]
    if data is not None:
        headers["Content-Type"] = "application/json"
    with request(base + path, "GET" if data is None else "POST",
                 None if data is None else json.dumps(data).encode(), headers) as response:
        return json.load(response)


def storage_url(url, host):
    parsed = urllib.parse.urlsplit(url)
    if parsed.hostname != host or parsed.username or parsed.password:
        raise RuntimeError("Storage host did not match the expected destination")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and host in {"localhost", "127.0.0.1"}):
        raise RuntimeError("Storage URL must use HTTPS (except loopback)")
    return urllib.parse.unquote(parsed.path).rsplit("/", 1)[-1]


def upload(base, plan, artifact, size, host, path):
    digest = hashlib.sha256()
    with path.open("wb") as output:
        remaining = size
        while remaining:
            chunk = os.urandom(min(1024 * 1024, remaining))
            output.write(chunk)
            digest.update(chunk)
            remaining -= len(chunk)
    identity = {"shard_plan_id": plan["id"]}
    if artifact is not None:
        identity["artifact"] = artifact
    # Reference lookup at start; exact plan lookup when signing/completing.
    start = {"reference": plan["reference"]}
    if artifact is not None:
        start["artifact"] = artifact
    upload_id = api(base, "/upload/start", start)["data"]["upload_id"]
    parts = []
    signing_seconds = 0
    put_seconds = 0
    started = time.monotonic()
    with path.open("rb") as source:
        while chunk := source.read(8 * 1024 * 1024):
            number = len(parts) + 1
            signing_started = time.monotonic()
            url = api(base, "/upload/generate-url", dict(identity, upload_id=upload_id, part_number=number))["data"]["url"]
            signing_seconds += time.monotonic() - signing_started
            name = storage_url(url, host)
            put_started = time.monotonic()
            with request(url, "PUT", chunk) as response:
                etag = response.headers.get("ETag")
                if not etag:
                    raise RuntimeError("Multipart response has no ETag")
            put_seconds += time.monotonic() - put_started
            parts.append({"part_number": number, "etag": etag.strip('"')})
    completion_started = time.monotonic()
    api(base, "/upload/complete", dict(identity, upload_id=upload_id, parts=parts))
    completion_seconds = time.monotonic() - completion_started
    elapsed = time.monotonic() - started
    print(json.dumps({"phase": "upload", "bytes": size, "seconds": elapsed, "parts": len(parts),
                      "signing_seconds": signing_seconds, "put_seconds": put_seconds,
                      "completion_seconds": completion_seconds}), flush=True)
    # Independent expected range, deliberately unaligned to S3 part boundaries.
    with path.open("rb") as source:
        source.seek(7 * 1024 * 1024 + 13)
        sample = source.read(4099)
    return name, {"size": size, "sha256": digest.hexdigest(), "range_sha256": hashlib.sha256(sample).hexdigest()}


def downloads(base, plan_id, host, expected=None):
    result = api(base, "/e2e/0?" + urllib.parse.urlencode({"shard_plan_id": plan_id}))
    urls = result.get("download_urls") or [result.get("download_url")]
    if not urls or not all(urls) or result.get("skip"):
        raise RuntimeError("Plan returned no runnable artifacts")
    names = [storage_url(url, host) for url in urls]
    if expected is not None and (len(names) != len(expected) or set(names) != set(expected)):
        raise RuntimeError("Plan returned the wrong artifact set")
    for url, name in zip(urls, names):
        started = time.monotonic()
        digest, size = hashlib.sha256(), 0
        with request(url) as response:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                size += len(chunk)
        elapsed = time.monotonic() - started
        if expected is not None:
            if size != expected[name]["size"] or digest.hexdigest() != expected[name]["sha256"]:
                raise RuntimeError("Downloaded artifact checksum/size mismatch")
            start = 7 * 1024 * 1024 + 13
            with request(url, headers={"Range": f"bytes={start}-{start + 4098}"}) as response:
                sample = response.read(4100)
                if response.status != 206 or response.headers.get("Content-Range") != f"bytes {start}-{start + 4098}/{size}":
                    raise RuntimeError("Range response has wrong status or bounds")
            if hashlib.sha256(sample).hexdigest() != expected[name]["range_sha256"]:
                raise RuntimeError("Range checksum mismatch")
        print(json.dumps({"phase": "download", "bytes": size, "seconds": elapsed,
                          "checksum_verified": expected is not None}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--storage-host", required=True, help="Expected signed URL hostname, not inferred from the response")
    parser.add_argument("--layout", choices=["split", "bundle"], default="split")
    parser.add_argument("--size-mib", type=int, default=512)
    parser.add_argument("--manifest", type=Path, help="Write plan IDs/checksums only; refuses an existing file")
    parser.add_argument("--read-manifest", type=Path, help="Recheck pinned artifacts after rollback/fault/recovery")
    parser.add_argument("--check-plan", help="Download a real CLI-created plan, asserting its storage host")
    args = parser.parse_args()
    url = os.environ["TUIST_URL"].rstrip("/")
    parsed = urllib.parse.urlsplit(url)
    if not ((parsed.scheme == "https" and parsed.netloc == "staging.tuist.dev") or
            (parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"})):
        raise RuntimeError("Only staging.tuist.dev or loopback is allowed")
    project = os.environ["TUIST_PROJECT"]
    if len(project.split("/")) != 2 or not project.split("/")[1].startswith("rustfs-e2e-"):
        raise RuntimeError("Use a dedicated rustfs-e2e-* project")
    if not 9 <= args.size_mib <= 2048:
        raise RuntimeError("size-mib must be 9..2048")
    if args.manifest and args.manifest.exists():
        raise RuntimeError("Refusing to overwrite manifest")
    base = url + "/api/projects/" + "/".join(urllib.parse.quote(p, safe="") for p in project.split("/")) + "/tests/shards"
    if args.check_plan:
        downloads(base, args.check_plan, args.storage_host)
    elif args.read_manifest:
        manifest = json.loads(args.read_manifest.read_text())
        if manifest["project"] != project or manifest["server"] != url:
            raise RuntimeError("Manifest belongs to another server/project")
        downloads(base, manifest["plan_id"], args.storage_host, manifest["objects"])
    else:
        plan = api(base, "", {"reference": "rustfs-e2e-" + str(uuid.uuid4()), "modules": ["E2ETests"], "shard_total": 1})
        objects = {}
        with tempfile.TemporaryDirectory(prefix="rustfs-e2e-") as directory:
            artifacts = ["shared", "module:E2ETests"] if args.layout == "split" else [None]
            for index, artifact in enumerate(artifacts):
                size = args.size_mib * 1024 * 1024 if index == 0 else 9 * 1024 * 1024 + 17
                name, expected = upload(base, plan, artifact, size, args.storage_host, Path(directory) / "payload")
                objects[name] = expected
        manifest = {"server": url, "project": project, "plan_id": plan["id"], "objects": objects}
        if args.manifest:
            with args.manifest.open("x") as output:
                json.dump(manifest, output, indent=2)
        downloads(base, plan["id"], args.storage_host, objects)
    print("PASS: shard storage checks completed")


if __name__ == "__main__":
    def deadline(_signum, _frame):
        raise RuntimeError("Qualification exceeded the 30-minute overall deadline")
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(1800)
    try:
        main()
    except (RuntimeError, KeyError, ValueError, OSError) as error:
        # Unknown parser/IO errors can contain credentials; print only our safe failures.
        print("FAIL: " + (str(error) if type(error) is RuntimeError else type(error).__name__), file=sys.stderr)
        sys.exit(1)
