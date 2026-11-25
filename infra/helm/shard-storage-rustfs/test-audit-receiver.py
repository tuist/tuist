#!/usr/bin/env python3
"""The RustFS audit receiver prints exactly one scrubbed line per S3 request.

Runs the receiver as a process and posts batches shaped like RustFS 1.0.6's
audit webhook, whose requestQuery holds the request headers, never the query.
The header-signed fixture assumes RustFS stops redacting Authorization and the
session token, and the presigned one carries its signature in the path; none
of it may reach stdout. Key IDs are hyphenated like the chart's own.
"""

import json
import os
import queue
import socket
import subprocess
import sys
import threading
import time
import urllib.request

RECEIVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "files", "audit_receiver.py")
SIGNATURE = "5ec7e75191a7e1b2c0ffee0123456789abcdef0123456789abcdef0123456789"
SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
TOKEN = "FwoGZXIvYXdzEJr//////////SESSIONTOKEN"
SECRETS = [SIGNATURE, SECRET_KEY, TOKEN, "X-Amz-Signature", "X-Amz-Credential", "X-Amz-Security-Token",
           "AWS4-HMAC-SHA256", "Signature=", "Credential="]
UA = "Boto3/1.44.11 md/Botocore#1.44.11"


def batch(entry):
    return {"EventName": entry["event"], "Key": f"{entry['api']['bucket']}/{entry['trigger']}", "Records": [entry]}


PRESIGNED_GET = batch({
    "version": "1.0", "time": 1795593596717, "event": "s3:ObjectAccessed:Get", "trigger": "s3:GetObject",
    "api": {"name": "s3:GetObject", "bucket": "actions-cache", "object": "acct-42/entry.tar",
            "status": "success", "status_code": 200, "timeToResponseInNS": "769274"},
    "remotehost": "10.2.3.4", "requestID": "81ddd675-fdc2-41bc-a18c-7a243c451554", "userAgent": "Python-urllib/3.12",
    "requestPath": f"/actions-cache/acct-42/entry.tar?X-Amz-Signature={SIGNATURE}&X-Amz-Security-Token={TOKEN}",
    "requestHost": "rustfs-s3.rustfs-production.svc.cluster.local:9000",
    "requestQuery": {
        "accept-encoding": "identity", "user-agent": "Python-urllib/3.12", "connection": "close",
        "host": "rustfs-s3.rustfs-production.svc.cluster.local:9000", "content-length": "0",
    },
    "responseHeader": {"accept-ranges": "bytes"},
    "accessKey": "rustfs-shards",
})

HEADER_PUT = batch({
    "version": "1.0", "time": 1795593596555, "event": "s3:ObjectCreated:Put", "trigger": "s3:PutObject",
    "api": {"name": "s3:PutObject", "bucket": "sandbox-archives", "object": "orb-7/archive.tar.zst",
            "status": "success", "status_code": 200, "timeToResponseInNS": "1891230"},
    "remotehost": "10.2.9.9", "requestID": "80cc6885-121b-4a44-b34a-b47d81da0083", "userAgent": UA,
    "requestPath": "/sandbox-archives/orb-7/archive.tar.zst",
    "requestQuery": {
        "authorization": f"AWS4-HMAC-SHA256 Credential=rustfs-shards/20261125/us-east-1/s3/aws4_request, "
                         f"SignedHeaders=host;x-amz-date, Signature={SIGNATURE}",
        "x-amz-security-token": TOKEN, "x-amz-content-sha256": "UNSIGNED-PAYLOAD",
        "x-amz-date": "20261125T075956Z", "content-length": "524465", "user-agent": UA,
        "x-amz-decoded-content-length": "524288",
    },
    "responseHeader": {},
    "accessKey": "rustfs-shards",
})

# RustFS 1.0.6 names a bulk delete's keys in api.objects and leaves api.object
# unset (rustfs/src/app/object/delete.rs).
BULK_DELETE = batch({
    "version": "1.0", "time": 1795593597019, "event": "s3:ObjectRemoved:Delete", "trigger": "s3:DeleteObjects",
    "api": {"name": "s3:DeleteObjects", "bucket": "actions-cache", "status": "success", "status_code": 200,
            "timeToResponseInNS": "1372636",
            "objects": [{"objectName": "acct-42/a.tar"}, {"objectName": "acct-42/what?.tar", "versionId": "null"},
                        {"objectName": f"x/X-Amz-Signature={SIGNATURE}"}]},
    "remotehost": "10.2.9.9", "requestID": "a8ecbfe4-2df4-4f5e-9b3a-e1eaa399a012", "userAgent": UA,
    "requestPath": "/actions-cache/",
    "requestQuery": {"authorization": "***redacted***", "content-length": "212", "user-agent": UA},
    "responseHeader": {},
    "accessKey": "rustfs-shards",
})


def expect(condition, message):
    if not condition:
        sys.exit(f"FAIL: {message}")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def post(port, body):
    data = body if isinstance(body, bytes) else json.dumps(body).encode()
    request = urllib.request.Request(f"http://127.0.0.1:{port}/audit", data=data, method="POST",
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status


def read_line(lines):
    try:
        return json.loads(lines.get(timeout=5))
    except queue.Empty:
        sys.exit("FAIL: receiver printed no line within 5 s")


def main():
    port = free_port()
    proc = subprocess.Popen([sys.executable, "-I", "-B", RECEIVER, str(port)],
                            stdout=subprocess.PIPE, text=True)
    lines = queue.Queue()
    threading.Thread(target=lambda: [lines.put(line) for line in proc.stdout], daemon=True).start()
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{port}/", method="HEAD"), timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        expect(post(port, PRESIGNED_GET) == 200, "presigned batch not acknowledged")
        presigned = read_line(lines)
        expect(post(port, HEADER_PUT) == 200, "header-signed batch not acknowledged")
        header = read_line(lines)
        expect(post(port, b"{not json") == 200, "unparseable batch must be acknowledged, not retried forever")
        dropped = read_line(lines)
        # One unreadable entry costs only itself, not its batch or the reply.
        broken = json.loads(json.dumps(HEADER_PUT["Records"][0]))
        broken["time"] = float("inf")
        mixed = {"Records": [broken, PRESIGNED_GET["Records"][0]]}
        expect(post(port, json.dumps(mixed).encode()) == 200, "batch with an unreadable entry not acknowledged")
        unreadable = read_line(lines)
        survivor = read_line(lines)
        expect(post(port, BULK_DELETE) == 200, "bulk delete batch not acknowledged")
        bulk = read_line(lines)
    finally:
        proc.terminate()
        proc.wait(timeout=5)
    time.sleep(0.2)
    rest = [lines.get() for _ in range(lines.qsize())]

    expect(rest == [], f"one line per request, got extra output: {rest!r}")
    expect(presigned == {
        "log": "rustfs_audit", "time": "2026-11-25T07:59:56.717+00:00", "client": "10.2.3.4",
        "api": "s3:GetObject", "bucket": "actions-cache", "object": "acct-42/entry.tar",
        "path": "/actions-cache/acct-42/entry.tar", "status": 200, "bytes_in": 0,
        "duration_ns": 769274, "auth": "presigned", "key_id": "rustfs-shards",
        "request_id": "81ddd675-fdc2-41bc-a18c-7a243c451554", "user_agent": "Python-urllib/3.12",
    }, f"presigned record: {presigned}")
    expect(header == {
        "log": "rustfs_audit", "time": "2026-11-25T07:59:56.555+00:00", "client": "10.2.9.9",
        "api": "s3:PutObject", "bucket": "sandbox-archives", "object": "orb-7/archive.tar.zst",
        "path": "/sandbox-archives/orb-7/archive.tar.zst", "status": 200, "bytes_in": 524288,
        "duration_ns": 1891230, "auth": "header", "key_id": "rustfs-shards",
        "request_id": "80cc6885-121b-4a44-b34a-b47d81da0083", "user_agent": UA,
    }, f"header-signed record: {header}")
    expect(dropped == {"log": "rustfs_audit_dropped", "reason": "unparseable", "bytes": 9}, f"drop marker: {dropped}")
    expect(unreadable == {"log": "rustfs_audit_dropped", "reason": "unreadable entry"}, f"entry marker: {unreadable}")
    expect(survivor == presigned, f"the rest of the batch was lost: {survivor}")
    # The signed-looking key is dropped from the list; the count still has it.
    expect(bulk == {
        "log": "rustfs_audit", "time": "2026-11-25T07:59:57.019+00:00", "client": "10.2.9.9",
        "api": "s3:DeleteObjects", "bucket": "actions-cache", "object": "", "path": "/actions-cache/",
        "status": 200, "bytes_in": 212, "duration_ns": 1372636, "auth": "header", "key_id": "rustfs-shards",
        "request_id": "a8ecbfe4-2df4-4f5e-9b3a-e1eaa399a012", "user_agent": UA,
        "objects": ["acct-42/a.tar", "acct-42/what?.tar"], "objects_count": 3,
    }, f"bulk delete record: {bulk}")
    for record in (presigned, header, bulk):
        line = json.dumps(record)
        for secret in SECRETS:
            expect(secret.lower() not in line.lower(), f"{secret!r} reached the log: {line}")

    # A key ID that is not a plain identifier, or a signed-looking object key,
    # is dropped rather than logged.
    sys.dont_write_bytecode = True
    sys.path.insert(0, os.path.dirname(RECEIVER))
    from audit_receiver import scrub
    odd = json.loads(json.dumps(HEADER_PUT["Records"][0]))
    odd["accessKey"] = SECRET_KEY  # "/" is never part of a key ID
    odd["api"]["object"] = f"x/X-Amz-Signature={SIGNATURE}"
    odd["requestPath"] = f"/b/Credential=rustfs-shards/{SIGNATURE}"
    odd["requestQuery"] = {}
    scrubbed = scrub(odd)
    expect(scrubbed["key_id"] == "" and scrubbed["object"] == "" and scrubbed["path"] == "" and scrubbed["auth"] == "none",
           f"suspicious values kept: {scrubbed}")
    # "=" and "," never occur in a RustFS key ID, so a value using them is dropped.
    for crafted in (f"rustfs-shards=X-Amz-Signature={SIGNATURE}", f"rustfs-shards,Signature={SIGNATURE}"):
        odd["accessKey"] = crafted
        expect(scrub(odd)["key_id"] == "", f"crafted key ID kept: {crafted}")
    # An object key is not a URL: "?" belongs to the name.
    odd["api"]["object"] = "dir/what?.txt"
    expect(scrub(odd)["object"] == "dir/what?.txt", f"object key cut: {scrub(odd)['object']}")
    print("PASS: presigned and header-signed requests each log one scrubbed record; no signature, credential or token")


if __name__ == "__main__":
    main()
