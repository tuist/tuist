"""Loopback-only control-plane fixture for the account rename ShellSpec."""
import http.server
import json
import pathlib
import sys

handle = "original"
aliases = [handle]


class ControlPlane(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def respond(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.respond({"peers": [], "account_handle": handle, "account_aliases": aliases,
                      "endpoint_redirects": {name + ".example.com": "https://" + handle + ".example.com"
                                             for name in aliases if name != handle},
                      "refresh_interval_seconds": 1, "replication_pull": False})

    def do_POST(self):
        global handle
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path in ("/rename", "/rename-again", "/rename-back"):
            handle = {"/rename": "renamed", "/rename-again": "latest", "/rename-back": "original"}[self.path]
            if handle not in aliases:
                aliases.append(handle)
            self.respond({})
        elif self.path == "/oauth2/introspect":
            self.respond({"active": True, "sub": "test", "principal_kind": "account",
                          "cache_grants": {"account": {"read": [], "write": []},
                                           "project": {"read": [handle + "/ios"],
                                                       "write": [handle + "/ios"]}}})
        else:
            self.respond({"accepted": 1})


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ControlPlane)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
