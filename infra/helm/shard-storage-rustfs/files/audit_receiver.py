"""Receives RustFS audit webhooks on loopback and prints one scrubbed JSON line
per S3 request to stdout, which Alloy ships to Pulse.

Each line is built from an allowlist of fields; nothing is copied wholesale.
RustFS puts the request headers in requestQuery (Authorization, presigned
parameters, security tokens), so that map is only inspected, never logged.
Any path-like value is cut at "?" and dropped if it still looks signed.

The receiver always answers 200 once it has read a body, so a malformed batch
or entry is counted and dropped rather than retried forever. RustFS queues records
while this process is down and never blocks S3 requests on delivery.
"""

import http.server
import json
import re
import sys
from datetime import datetime, timezone

MAX_BODY = 4 * 1024 * 1024
# Access key IDs as RustFS accepts them; the chart's own contain hyphens.
# RustFS reserves "=" and ",", which would otherwise let a crafted value carry
# a signature.
KEY_ID = re.compile(r"^[A-Za-z0-9._@+-]{1,128}$")
SIGNED = re.compile(
    r"x-amz-(signature|credential|security-token)|aws4-hmac-sha256|signature=|credential=|awsaccesskeyid=",
    re.IGNORECASE,
)


MAX_OBJECTS_CHARS = 4096


def _text(value, limit=1024, query=True):
    """A bounded string, cut at "?" when it may be a URL, and empty if it still
    looks signed."""
    if not isinstance(value, str):
        return ""
    if query:
        value = value.split("?", 1)[0]
    value = value[:limit]
    return "" if SIGNED.search(value) else value


def _objects(api):
    """The keys a DeleteObjects call names, up to MAX_OBJECTS_CHARS in all."""
    names = api.get("objects") if isinstance(api.get("objects"), list) else []
    keys, size = [], 0
    for item in names:
        key = _text(item.get("objectName"), query=False) if isinstance(item, dict) else ""
        if not key or size + len(key) > MAX_OBJECTS_CHARS:
            continue
        keys.append(key)
        size += len(key)
    return keys, len(names)


def _int(value):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    return number if number >= 0 else None


def _time(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return datetime.fromtimestamp(value / 1000, tz=timezone.utc).isoformat(timespec="milliseconds")
    return _text(value, 64)


def scrub(entry):
    """Returns the logged fields of one RustFS audit entry."""
    api = entry.get("api") if isinstance(entry.get("api"), dict) else {}
    headers = entry.get("requestQuery") if isinstance(entry.get("requestQuery"), dict) else {}
    names = {str(name).lower() for name in headers}
    key_id = entry.get("accessKey")
    key_id = key_id if isinstance(key_id, str) and KEY_ID.match(key_id) else ""
    if "authorization" in names:
        auth = "header"
    elif names & {"x-amz-signature", "x-amz-credential", "signature", "awsaccesskeyid"} or key_id:
        auth = "presigned"
    else:
        auth = "none"
    line = {
        "time": _time(entry.get("time")),
        "client": _text(entry.get("remotehost"), 64),
        "api": _text(api.get("name"), 64),
        "bucket": _text(api.get("bucket"), 64),
        # An object key, not a URL: "?" is part of the name.
        "object": _text(api.get("object"), query=False),
        "path": _text(entry.get("requestPath")),
        "status": _int(api.get("status_code")),
        # The object bytes of an aws-chunked upload, else the body's length.
        # RustFS reports no response size.
        "bytes_in": _int(headers.get("x-amz-decoded-content-length", headers.get("content-length"))),
        "duration_ns": _int(api.get("timeToResponseInNS")),
        "auth": auth,
        "key_id": key_id,
        "request_id": _text(entry.get("requestID"), 64),
        "user_agent": _text(entry.get("userAgent"), 256),
    }
    # A bulk delete (DeleteObjects) names its keys here, not in api.object.
    keys, count = _objects(api)
    if count:
        line["objects"] = keys
        line["objects_count"] = count
    return line


def entries(body):
    """The audit entries in one webhook body: a batch or a single entry."""
    payload = json.loads(body)
    if isinstance(payload, dict) and isinstance(payload.get("Records"), list):
        return [record for record in payload["Records"] if isinstance(record, dict)]
    if isinstance(payload, dict) and "api" in payload:
        return [payload]
    raise ValueError("not an audit entry")


def lines(body):
    out = []
    for entry in entries(body):
        try:
            out.append(json.dumps({"log": "rustfs_audit", **scrub(entry)}, separators=(",", ":")))
        except Exception:
            out.append(json.dumps({"log": "rustfs_audit_dropped", "reason": "unreadable entry"}))
    return out


class Handler(http.server.BaseHTTPRequestHandler):
    def _ok(self):
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self):
        self._ok()

    def do_POST(self):
        length = _int(self.headers.get("Content-Length"))
        if length is None or length > MAX_BODY:
            self.send_response(413)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.close_connection = True
            return
        body = self.rfile.read(length)
        try:
            out = lines(body)
        except Exception:
            out = [json.dumps({"log": "rustfs_audit_dropped", "reason": "unparseable", "bytes": length})]
        sys.stdout.write("".join(line + "\n" for line in out))
        sys.stdout.flush()
        self._ok()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9900
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
