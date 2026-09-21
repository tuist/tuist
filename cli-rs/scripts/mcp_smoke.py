#!/usr/bin/env python3
"""Starts `tuist --mcp` over stdio and calls real Tuist commands through it.

Usage: cli-rs/scripts/mcp_smoke.py <tuist-binary> <project-dir>

Fails unless the tool list excludes hidden commands, `version` succeeds, `dump project`
returns the manifest as JSON, and a failing command reports its non-zero exit code.
"""

import json
import subprocess
import sys


def main() -> int:
    binary, project = sys.argv[1], sys.argv[2]
    server = subprocess.Popen(
        [binary, "--mcp"],
        cwd=project,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    next_id = 0

    def request(method, params):
        nonlocal next_id
        next_id += 1
        server.stdin.write(json.dumps({"jsonrpc": "2.0", "id": next_id, "method": method, "params": params}) + "\n")
        server.stdin.flush()
        while True:
            message = json.loads(server.stdout.readline())
            if message.get("id") == next_id:
                if "error" in message:
                    raise RuntimeError(f"{method} failed: {message['error']}")
                return message["result"]

    def structured(result):
        return result.get("structuredContent") or json.loads(result["content"][0]["text"])

    # The server uses progressive discovery: commands are found with search_tools and
    # run through call_write_tool (none of them are marked read-only).
    def call(name, arguments):
        result = request("tools/call", {
            "name": "call_write_tool",
            "arguments": {"name": name, "arguments": {"arguments": arguments}},
        })
        return structured(result)

    def all_tools():
        names, offset = [], 0
        while offset is not None:
            page = structured(request("tools/call", {
                "name": "search_tools",
                "arguments": {"query": "", "offset": offset, "limit": 50},
            }))
            names += [tool["name"] for tool in page["tools"]]
            offset = page.get("nextOffset")
        return names

    failures = []

    def check(label, condition, detail=""):
        print(("ok    " if condition else "FAIL  ") + label + (f"  ({detail})" if detail and not condition else ""))
        if not condition:
            failures.append(label)

    request("initialize", {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "mcp_smoke", "version": "0"},
    })
    server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    server.stdin.flush()

    tools = set(all_tools())
    check("tools listed", len(tools) > 50, f"{len(tools)} tools")
    check("hidden command not listed", "analytics-upload" not in tools)
    check("generate run listed", "generate_run" in tools, sorted(tools)[:10])
    details = structured(request("tools/call", {"name": "get_tool_details", "arguments": {"name": "generate_run"}}))
    check("generate run takes an arguments array",
          details["inputSchema"]["properties"]["arguments"]["type"] == "array", details)

    version = call("version", [])
    check("version exits 0", version.get("exitCode") == 0, version)

    dump = call("dump", ["project"])
    check("dump exits 0", dump.get("exitCode") == 0, dump.get("stderr", "")[:300])
    check("dump returns the manifest", isinstance(dump.get("json"), dict) and "targets" in dump["json"], str(dump)[:300])

    bad = call("generate_run", ["--bogus-flag"])
    check("bad flag reports exit 64", bad.get("exitCode") == 64, bad)

    prompt = request("tools/call", {
        "name": "call_write_tool",
        "arguments": {"name": "init", "arguments": {"arguments": []}},
    })
    prompt_text = prompt["content"][0]["text"] if prompt.get("content") else ""
    check("prompting command fails with the question it could not ask",
          prompt.get("isError") is True and "How would you like to start with Tuist?" in prompt_text,
          json.dumps(prompt)[:300])

    server.stdin.close()
    server.wait(timeout=30)
    print()
    print("all MCP checks passed" if not failures else f"{len(failures)} MCP check(s) failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
