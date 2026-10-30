"""Explicit post-build publisher using Tuist authentication and artifact receipts."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import apple

import android


def canonical(value):
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode()


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def package(payload, media_type, interface, metadata, directory):
    blobs = {}

    def content(path, media):
        with path.open("rb") as stream:
            checksum = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
        blobs[checksum] = path
        return {
            "digest": checksum,
            "size_bytes": path.stat().st_size,
            "media_type": media,
        }

    def document(name, value, media):
        path = directory / name
        path.write_bytes(canonical(value))
        return content(path, media)

    manifest = document(
        "artifact.json",
        {
            "schema": "once.artifact.v1",
            "payloads": {
                "product": content(payload, media_type),
                "metadata": document("metadata.json", metadata, "application/json"),
            },
            "interfaces": {
                interface: {
                    "payload": "product",
                    "spec": {"metadata_payload": "metadata"},
                }
            },
        },
        "application/vnd.once.artifact.v1+json",
    )
    root = document(
        "set.json",
        {
            "schema": "once.artifact_set.v1",
            "members": {"product": {"artifact": manifest, "selectors": {}}},
        },
        "application/vnd.once.artifact-set.v1+json",
    )
    return root, blobs


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Service:
    def __init__(self, url, project, token):
        parts = urllib.parse.urlsplit(url)
        if (
            (
                parts.scheme != "https"
                and not (
                    parts.scheme == "http"
                    and parts.hostname in ("localhost", "127.0.0.1", "::1")
                )
            )
            or not parts.hostname
            or parts.username
            or parts.password
            or parts.query
            or parts.fragment
            or parts.path not in ("", "/")
        ):
            raise ValueError(
                "Use an HTTPS Tuist origin (HTTP is allowed only for loopback development)"
            )
        handles = project.split("/")
        if len(handles) != 2 or not all(
            handle and all(c.isascii() and (c.isalnum() or c in "-_") for c in handle)
            for handle in handles
        ):
            raise ValueError("--project must be an account/project handle")
        self.base = url.rstrip("/") + "/api/projects/" + project + "/artifacts"
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, path, body=None, size=None):
        headers = {
            "Authorization": "Bearer " + self.token,
            "Content-Type": "application/octet-stream"
            if size is not None
            else "application/json",
        }
        if size is not None:
            headers["Content-Length"] = str(size)
        request = urllib.request.Request(
            self.base + path, data=body, headers=headers, method=method
        )
        try:
            with self.opener.open(request, timeout=120) as response:
                data = response.read(1_048_577)
                if len(data) > 1_048_576:
                    raise ValueError("Artifact service response exceeds 1 MiB")
                value = json.loads(data) if data else None
                if method == "GET" and value is None:
                    raise ValueError(
                        "Invalid artifact lookup; publication is not confirmed"
                    )
                return value
        except urllib.error.HTTPError as error:
            if method == "GET" and error.code == 404:
                return None
            raise ValueError(
                f"Artifact service rejected {method} (HTTP {error.code}); publication is not confirmed"
            ) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            raise ValueError(
                "Artifact service unavailable; publication is not confirmed"
            ) from None


def publish(service, intent, blobs):
    capabilities = service.request("GET", "/")
    if (
        not isinstance(capabilities, dict)
        or capabilities.get("schema") != "once.publication_service.v1"
        or not capabilities.get("destination")
    ):
        raise ValueError("The Tuist server does not support artifact publication")
    key = digest(canonical(intent))
    path = "/publications/" + key

    def confirm(receipt):
        if not isinstance(receipt, dict) or any(
            receipt.get(field) != expected
            for field, expected in {
                "schema": "once.publication_receipt.v1",
                "key": key,
                "root": intent["root"],
                "destination": capabilities["destination"],
            }.items()
        ):
            raise ValueError("Invalid artifact receipt; publication is not confirmed")

    receipt = service.request("GET", path)
    if receipt is not None:
        confirm(receipt)
        return "Already published", key
    for checksum, blob in blobs.items():
        with blob.open("rb") as stream:
            service.request(
                "POST", path + "/content/" + checksum, stream, blob.stat().st_size
            )
    confirm(service.request("POST", path, canonical(intent)))
    return "Published", key


def main():
    parser = argparse.ArgumentParser(
        description="Build an application and explicitly publish a Tuist preview."
    )
    parser.add_argument("--config", required=True)
    parser.add_argument("--payload", required=True)
    parser.add_argument(
        "--publish",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Authorize publication to --url and --project for this invocation only",
    )
    parser.add_argument("--project", help="Tuist account/project handle")
    parser.add_argument("--url", default="https://tuist.dev")
    parser.add_argument("--track")
    parser.add_argument("--revision")
    parser.add_argument("--apkanalyzer")
    parser.add_argument("--apksigner")
    args = parser.parse_args()
    if not args.publish:
        print(
            "Publication disabled. Pass --publish --project account/project to authorize this invocation."
        )
        return
    if not args.project:
        parser.error("--publish requires --project account/project")
    # Validate destination before invoking the authentication helper or any network.
    service = Service(args.url, args.project, "")
    config = json.loads(Path(args.config).read_text())
    payload = Path(args.payload)
    with tempfile.TemporaryDirectory(prefix="tuist-bazel-preview-") as temporary:
        directory = Path(temporary)
        # Verify and upload the same snapshot, even if another build replaces
        # the original Bazel output while publication is running.
        snapshot = directory / "input"
        shutil.copyfile(payload, snapshot)
        producer = {"android": android, "apple": apple}[config["ecosystem"]]
        result = producer.prepare(snapshot, directory, args)
        metadata = result[-1]
        identifier = metadata.get("application_id") or metadata.get("bundle_identifier")
        if not isinstance(identifier, str) or not identifier:
            raise ValueError("The application has no native identifier")
        for field in [
            "application_id",
            "bundle_identifier",
            "display_name",
            "version",
            "build_version",
            "version_code",
            "version_name",
        ]:
            value = metadata.get(field)
            if value is not None and (
                not isinstance(value, str) or len(value.encode()) > 255 or "\0" in value
            ):
                raise ValueError(
                    "Native application metadata is not eligible for a preview"
                )
        root, blobs = package(*result, directory)
        token = subprocess.run(
            ["tuist", "auth", "token", "--url", args.url],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if not token or any(char.isspace() for char in token):
            raise ValueError(
                "Tuist did not return an authentication token; run tuist auth login"
            )
        service.token = token
        intent = {
            "schema": "once.publication_intent.v1",
            "target": config["target"],
            "root": root,
            "track": args.track,
            "revision": args.revision,
        }
        status, key = publish(service, intent, blobs)
        print(
            f"{status} {key}. Preview processing is asynchronous: {args.url.rstrip('/')}/{args.project}/previews"
        )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # Do not print captured helper output, native signing diagnostics or tokens.
        if isinstance(error, subprocess.CalledProcessError):
            message = f"{Path(error.cmd[0]).name} exited {error.returncode}; publication was not attempted"
        elif isinstance(error, ValueError):
            message = str(error)
        else:
            message = "Authentication, packaging or native verification failed"
        print("Tuist preview: " + message, file=sys.stderr)
        sys.exit(1)
