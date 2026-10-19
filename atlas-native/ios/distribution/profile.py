"""Validate Atlas's ad-hoc profile and derive signing inputs without secrets."""

import datetime
import fnmatch
import hashlib
import plistlib
import re
import sys
from pathlib import Path

BUNDLE_ID = "dev.tuist.atlas"
TEAM_ID = "U6LC622NKF"


def signing_inputs(profile, info, identities, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    expiration = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
    if expiration <= now:
        raise ValueError("The Atlas provisioning profile has expired")
    if profile.get("TeamIdentifier") != [TEAM_ID]:
        raise ValueError("Expected the Tuist GmbH provisioning team")
    if not profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ValueError("An ad-hoc profile with registered devices is required")
    entitlements = profile["Entitlements"]
    if entitlements.get("get-task-allow") is not False:
        raise ValueError("Use an ad-hoc distribution profile, not a development profile")
    if entitlements.get("com.apple.developer.team-identifier") != TEAM_ID:
        raise ValueError("The profile entitlement team does not match Tuist GmbH")
    prefix = profile["ApplicationIdentifierPrefix"][0]
    application_id = f"{prefix}.{BUNDLE_ID}"
    if entitlements.get("application-identifier") != application_id:
        raise ValueError("The profile must explicitly provision dev.tuist.atlas")
    if not any(fnmatch.fnmatchcase(application_id, group) for group in entitlements.get("keychain-access-groups", [])):
        raise ValueError("The profile must allow Atlas's Keychain access group")
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "Atlas":
        raise ValueError("Expected the production Atlas application")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"] or info.get("DTPlatformName") != "iphoneos":
        raise ValueError("Build AtlasIOSDevice, not the simulator application")

    certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile["DeveloperCertificates"]}
    identity = next(
        (fingerprint for fingerprint, name in re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
         if fingerprint.upper() in certificates and name.startswith(("Apple Distribution:", "iPhone Distribution:"))),
        None,
    )
    if not identity:
        raise ValueError("No valid distribution identity matches the provisioning profile")
    return identity, {
        "application-identifier": application_id,
        "com.apple.developer.team-identifier": TEAM_ID,
        "keychain-access-groups": [application_id],
        "get-task-allow": False,
    }


def main():
    profile_path, info_path, identities_path, entitlements_path = map(Path, sys.argv[1:])
    identity, entitlements = signing_inputs(
        plistlib.loads(profile_path.read_bytes()),
        plistlib.loads(info_path.read_bytes()),
        identities_path.read_text(),
    )
    entitlements_path.write_bytes(plistlib.dumps(entitlements))
    print(identity)


if __name__ == "__main__":
    main()
