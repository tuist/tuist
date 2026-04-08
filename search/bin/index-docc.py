#!/usr/bin/env python3
"""Index a DocC site into TypeSense by crawling its JSON data endpoints."""

import json
import os
import re
import sys
import urllib.request
import urllib.error
from datetime import datetime

BASE_URL = "https://projectdescription.tuist.dev"
TYPESENSE_HOST = os.environ.get("TYPESENSE_HOST", "http://localhost:18108")
TYPESENSE_API_KEY = os.environ["TYPESENSE_API_KEY"]
COLLECTION = "projectdescription"

visited = set()
documents = []


def fetch_json(path):
    url = f"{BASE_URL}/data{path}.json"
    try:
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "Mozilla/5.0 (compatible; TuistSearchIndexer/1.0)")
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError:
        return None


def extract_text(content_items):
    """Extract plain text from DocC content nodes."""
    texts = []
    for item in content_items:
        if item.get("type") == "paragraph":
            for inline in item.get("inlineContent", []):
                if inline.get("type") == "text":
                    texts.append(inline["text"])
                elif inline.get("type") == "codeVoice":
                    texts.append(inline.get("code", ""))
        elif item.get("type") == "heading":
            texts.append(item.get("text", ""))
        elif item.get("type") == "unorderedList":
            for li in item.get("items", []):
                for c in li.get("content", []):
                    texts.extend(extract_text([c]))
    return texts


def process_page(path):
    if path in visited:
        return
    visited.add(path)

    data = fetch_json(path)
    if not data:
        return

    metadata = data.get("metadata", {})
    title = metadata.get("title", "")
    role = metadata.get("roleHeading", "")
    url = f"{BASE_URL}/documentation{path.replace('/documentation', '')}"

    # Extract content text
    content_parts = []
    for section in data.get("primaryContentSections", []):
        if section.get("kind") == "content":
            content_parts.extend(extract_text(section.get("content", [])))
        elif section.get("kind") == "parameters":
            for param in section.get("parameters", []):
                content_parts.append(f"{param.get('name', '')}: {' '.join(extract_text(param.get('content', [])))}")

    # Extract abstract
    abstract_parts = []
    for item in data.get("abstract", []):
        if item.get("type") == "text":
            abstract_parts.append(item["text"])

    content = " ".join(content_parts)
    abstract = " ".join(abstract_parts)

    if title:
        documents.append({
            "title": title,
            "role": role,
            "abstract": abstract,
            "content": content[:10000],
            "url": url,
            "path": path,
            "hierarchy.lvl0": "ProjectDescription",
            "hierarchy.lvl1": role,
            "hierarchy.lvl2": title,
        })

    # Follow references to child pages
    for ref_id, ref in data.get("references", {}).items():
        ref_url = ref.get("url", "")
        if ref_url.startswith("/documentation/") and ref.get("type") == "topic":
            process_page(ref_url)

    # Follow topic sections
    for section in data.get("topicSections", []):
        for ident in section.get("identifiers", []):
            ref = data.get("references", {}).get(ident, {})
            ref_url = ref.get("url", "")
            if ref_url.startswith("/documentation/"):
                process_page(ref_url)


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
    print(f"Crawling DocC site at {BASE_URL}...")
    process_page("/documentation/projectdescription")
    print(f"Found {len(documents)} pages")

    # Delete existing collection if it exists
    typesense_request("DELETE", f"/collections/{COLLECTION}")

    # Create collection
    schema = {
        "name": COLLECTION,
        "fields": [
            {"name": "title", "type": "string"},
            {"name": "role", "type": "string", "facet": True},
            {"name": "abstract", "type": "string"},
            {"name": "content", "type": "string"},
            {"name": "url", "type": "string", "index": False},
            {"name": "path", "type": "string", "index": False},
            {"name": "hierarchy.lvl0", "type": "string", "facet": True},
            {"name": "hierarchy.lvl1", "type": "string", "facet": True, "optional": True},
            {"name": "hierarchy.lvl2", "type": "string", "facet": True, "optional": True},
        ],
    }
    typesense_request("POST", "/collections", schema)
    print(f"Created collection '{COLLECTION}'")

    # Import documents
    lines = "\n".join(json.dumps(doc) for doc in documents)
    url = f"{TYPESENSE_HOST}/collections/{COLLECTION}/documents/import?action=create"
    req = urllib.request.Request(url, data=lines.encode(), method="POST")
    req.add_header("X-TYPESENSE-API-KEY", TYPESENSE_API_KEY)
    req.add_header("Content-Type", "text/plain")
    with urllib.request.urlopen(req) as resp:
        results = resp.read().decode().strip().split("\n")
        successes = sum(1 for r in results if json.loads(r).get("success"))
        print(f"Indexed {successes}/{len(documents)} documents into '{COLLECTION}'")


if __name__ == "__main__":
    main()
