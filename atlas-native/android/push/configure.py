#!/usr/bin/env python3
"""Import public Android Firebase app identifiers. Never accepts service-account JSON."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def public_identifiers(document):
    if document.get("type") == "service_account" or "private_key" in document:
        raise ValueError("Use the Android google-services.json, never a service-account credential")
    clients = [client for client in document.get("client", [])
               if client.get("client_info", {}).get("android_client_info", {}).get("package_name") == "dev.tuist.atlas"]
    if len(clients) != 1:
        raise ValueError("Expected exactly one dev.tuist.atlas Android Firebase app")
    client = clients[0]
    project = document.get("project_info", {})
    keys = client.get("api_key", [])
    values = {
        "atlas_firebase_application_id": client.get("client_info", {}).get("mobilesdk_app_id"),
        "atlas_firebase_project_id": project.get("project_id"),
        "atlas_firebase_sender_id": project.get("project_number"),
        "atlas_firebase_api_key": keys[0].get("current_key") if len(keys) == 1 else None,
    }
    if any(not isinstance(value, str) or not 1 <= len(value) <= 256 or
           any(ord(character) < 32 for character in value) for value in values.values()):
        raise ValueError("Missing or invalid public Firebase identifiers")
    return values


def render(values):
    resources = ET.Element("resources")
    resources.append(ET.Comment(" Public Firebase identifiers, never a service-account key. "))
    for name, value in values.items():
        ET.SubElement(resources, "string", name=name, translatable="false").text = value
    ET.indent(resources, space="    ")
    return '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(resources, encoding="unicode") + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("google_services", type=Path)
    arguments = parser.parse_args()
    values = public_identifiers(json.loads(arguments.google_services.read_text()))
    output = ROOT / "android/res/values/push.xml"
    output.write_text(render(values))
    print(f"Updated {output.relative_to(ROOT)} with public identifiers. Rebuild and review the diff before committing.")
