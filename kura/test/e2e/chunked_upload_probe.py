#!/usr/bin/env python3
"""Exercise negotiated uploads and legacy reads, optionally across two nodes."""
import argparse
import hashlib
import json
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("writer")
    parser.add_argument("reader")
    parser.add_argument("--tenant", default="default")
    args = parser.parse_args()
    project = f"chunk-probe-{uuid.uuid4().hex}"
    pieces = [b"first chunk" * 20000, b"second chunk" * 20000]
    whole = b"".join(pieces)

    def digest(data):
        return {"hash": hashlib.sha256(data).hexdigest(), "size": len(data)}

    def request(base, path, kind, method="GET", data=None, extra=None, headers=None):
        query = {"tenant_id": args.tenant, "namespace_id": project, "kind": kind, **(extra or {})}
        if isinstance(data, dict):
            data = json.dumps(data).encode()
            headers = {"Content-Type": "application/json", **(headers or {})}
        req = urllib.request.Request(base.rstrip("/") + path + "?" + urllib.parse.urlencode(query), data=data, method=method, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=10) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.read()

    for kind in ["module", "gradle"]:
        prefix = "/api/cache/chunks/"
        status, body = request(args.writer, prefix + "capabilities", kind)
        assert status == 200 and json.loads(body)["version"] == 1
        chunks = [digest(piece) for piece in pieces]
        target = {"hash": "artifact", "name": "Fixture", "cache_category": "builds", "cache_key": "abcdef"}
        completion = {"blob": digest(whole), "chunks": chunks}
        assert request(args.writer, prefix + "complete", kind, "POST", completion, target)[0] == 409
        for piece, chunk in zip(pieces, chunks):
            assert request(args.writer, prefix + "upload", kind, "PUT", piece, chunk)[0] == 204
        status, body = request(args.writer, prefix + "missing", kind, "POST", {"chunks": chunks})
        assert status == 200 and json.loads(body)["missing"] == []
        assert request(args.writer, prefix + "complete", kind, "POST", completion, target)[0] == 204
        path = "/api/cache/gradle/abcdef" if kind == "gradle" else "/api/cache/module/artifact"
        deadline = time.monotonic() + 30
        while True:
            status, body = request(args.reader, path, kind, extra=target)
            if status == 200:
                break
            assert time.monotonic() < deadline, (kind, status, body)
            time.sleep(0.1)
        assert body == whole
        status, body = request(args.reader, path, kind, extra=target, headers={"Range": "bytes=3-42"})
        assert status == 206 and body == whole[3:43]
        print(f"{kind}: negotiated upload, missing-chunk rejection, legacy read and range passed")


if __name__ == "__main__":
    main()
