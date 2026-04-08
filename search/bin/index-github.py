#!/usr/bin/env python3
"""Index GitHub issues and PRs from tuist/tuist into TypeSense."""

import json
import os
import sys
import urllib.request
import urllib.error
import time

GITHUB_REPO = "tuist/tuist"
TYPESENSE_HOST = os.environ.get("TYPESENSE_HOST", "http://localhost:18108")
TYPESENSE_API_KEY = os.environ["TYPESENSE_API_KEY"]
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
COLLECTION = "github-issues"


def github_request(url):
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "TuistSearchIndexer/1.0")
    if GITHUB_TOKEN:
        req.add_header("Authorization", f"Bearer {GITHUB_TOKEN}")
    try:
        with urllib.request.urlopen(req) as resp:
            link_header = resp.getheader("Link", "")
            data = json.loads(resp.read())
            # Parse next page URL from Link header
            next_url = None
            for part in link_header.split(","):
                if 'rel="next"' in part:
                    next_url = part.split(";")[0].strip().strip("<>")
            return data, next_url
    except urllib.error.HTTPError as e:
        if e.code == 403:
            # Rate limited — wait and retry
            reset = int(e.headers.get("X-RateLimit-Reset", time.time() + 60))
            wait = max(reset - int(time.time()), 1)
            print(f"Rate limited, waiting {wait}s...", file=sys.stderr)
            time.sleep(wait)
            return github_request(url)
        raise


def fetch_all_issues(kind="issues"):
    """Fetch all issues or PRs, paginating through results."""
    state = "all"
    url = f"https://api.github.com/repos/{GITHUB_REPO}/{kind}?state={state}&per_page=100&sort=updated&direction=desc"
    all_items = []

    while url:
        items, next_url = github_request(url)
        if not items:
            break
        all_items.extend(items)
        url = next_url
        print(f"  Fetched {len(all_items)} {kind}...", end="\r")

    print(f"  Fetched {len(all_items)} {kind}     ")
    return all_items


def typesense_request(method, path, body=None):
    url = f"{TYPESENSE_HOST}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("X-TYPESENSE-API-KEY", TYPESENSE_API_KEY)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code in (404, 409):
            return None
        error_body = e.read().decode()
        print(f"Error {e.code}: {error_body}", file=sys.stderr)
        raise


def main():
    print(f"Fetching issues and PRs from {GITHUB_REPO}...")
    issues = fetch_all_issues("issues")

    documents = []
    for item in issues:
        is_pr = "pull_request" in item
        labels = [l["name"] for l in item.get("labels", [])]
        body = (item.get("body") or "")[:10000]

        documents.append({
            "title": item["title"],
            "content": body,
            "url": item["html_url"],
            "number": item["number"],
            "state": item["state"],
            "kind": "pull-request" if is_pr else "issue",
            "labels": labels,
            "author": item.get("user", {}).get("login", ""),
            "created_at": item.get("created_at", ""),
            "updated_at": item.get("updated_at", ""),
            "hierarchy.lvl0": "Pull Requests" if is_pr else "Issues",
            "hierarchy.lvl1": item["title"],
        })

    print(f"Prepared {len(documents)} documents")

    # Delete existing collection
    typesense_request("DELETE", f"/collections/{COLLECTION}")

    # Create collection
    schema = {
        "name": COLLECTION,
        "fields": [
            {"name": "title", "type": "string"},
            {"name": "content", "type": "string"},
            {"name": "url", "type": "string", "index": False},
            {"name": "number", "type": "int64"},
            {"name": "state", "type": "string", "facet": True},
            {"name": "kind", "type": "string", "facet": True},
            {"name": "labels", "type": "string[]", "facet": True},
            {"name": "author", "type": "string", "facet": True},
            {"name": "created_at", "type": "string"},
            {"name": "updated_at", "type": "string"},
            {"name": "hierarchy.lvl0", "type": "string", "facet": True},
            {"name": "hierarchy.lvl1", "type": "string"},
        ],
    }
    typesense_request("POST", "/collections", schema)
    print(f"Created collection '{COLLECTION}'")

    # Import in batches
    batch_size = 250
    total_success = 0
    for i in range(0, len(documents), batch_size):
        batch = documents[i:i + batch_size]
        lines = "\n".join(json.dumps(doc) for doc in batch)
        url = f"{TYPESENSE_HOST}/collections/{COLLECTION}/documents/import?action=create"
        req = urllib.request.Request(url, data=lines.encode(), method="POST")
        req.add_header("X-TYPESENSE-API-KEY", TYPESENSE_API_KEY)
        req.add_header("Content-Type", "text/plain")
        with urllib.request.urlopen(req) as resp:
            results = resp.read().decode().strip().split("\n")
            successes = sum(1 for r in results if json.loads(r).get("success"))
            total_success += successes

    print(f"Indexed {total_success}/{len(documents)} documents into '{COLLECTION}'")


if __name__ == "__main__":
    main()
