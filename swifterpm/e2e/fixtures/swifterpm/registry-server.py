import http.server
import json
import pathlib
import socketserver
import sys
import urllib.parse
import zipfile

registry_dir = pathlib.Path(sys.argv[1])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def send_json(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        # SwiftPM validates Content-Type against a closed list (see
        # RegistryClient.ContentType): bare `application/json` for JSON
        # responses, not the vendor `application/vnd.swift.registry.v1+json`
        # form. Likewise it requires Content-Version: 1 (validateAPIVersion).
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Version", "1")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/availability":
            # SwiftPM probes this endpoint before any registry call when
            # --default-registry-url is set (SwiftCommandState hardcodes
            # supportsAvailability: true). Reply 200 so the resolver proceeds
            # to the identifier / version / archive endpoints below.
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if parsed.path == "/identifiers":
            source_url = urllib.parse.parse_qs(parsed.query).get("url", [""])[0].lower()
            if "proto" in source_url:
                self.send_json({"identifiers": ["apple.swift-protobuf"]})
                return
            if "service" in source_url:
                self.send_json({"identifiers": ["grpc.grpc-swift-protobuf"]})
                return
            self.send_json({"identifiers": ["example.registryfoo"]})
            return
        if parsed.path == "/apple/swift-protobuf":
            self.send_json({"releases": {}})
            return
        if parsed.path == "/grpc/grpc-swift-protobuf":
            self.send_json({"releases": {}})
            return
        if parsed.path == "/example/registryfoo":
            if (registry_dir / "no-releases").exists():
                self.send_json({"releases": {}})
                return
            self.send_json({"releases": {"1.0.0": {}}})
            return
        if parsed.path == "/example/registryfoo/1.0.0":
            checksum = (registry_dir / "checksum.txt").read_text().strip()
            # SwiftPM's VersionMetadata decoder (RegistryClient.swift) requires
            # `id` and `version` to be present alongside `resources`.
            self.send_json({
                "id": "example.registryfoo",
                "version": "1.0.0",
                "resources": [
                    {
                        "name": "source-archive",
                        "type": "application/zip",
                        "checksum": checksum,
                    }
                ]
            })
            return
        if parsed.path == "/example/registryfoo/1.0.0/Package.swift":
            # SwiftPM fetches the manifest separately from the source archive
            # during registry resolution. Extract Package.swift from the
            # pre-built archive so the server stays self-contained.
            archive = registry_dir / "registryfoo.zip"
            with zipfile.ZipFile(archive) as zf:
                manifest = zf.read("Package.swift")
            self.send_response(200)
            self.send_header("Content-Type", "text/x-swift")
            self.send_header("Content-Version", "1")
            self.send_header("Content-Length", str(len(manifest)))
            self.end_headers()
            self.wfile.write(manifest)
            return
        if parsed.path == "/example/registryfoo/1.0.0.zip":
            data = (registry_dir / "registryfoo.zip").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Version", "1")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_response(404)
        self.end_headers()


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    print(httpd.server_address[1], flush=True)
    httpd.serve_forever()
