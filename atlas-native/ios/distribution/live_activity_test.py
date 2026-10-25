"""Credential-free WidgetKit build declarations, embedding and signing fixtures.

On macOS the profile fixtures use real PlistBuddy/plutil/date. Elsewhere only
those platform tools are simulated; signing and Xcode tools are always fakes.
"""

import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


DIRECTORY = Path(__file__).resolve().parent
MODULES = DIRECTORY.parents[1] / "modules"
CERTIFICATE = b"fixture distribution certificate, not a real identity"
IDENTITY = hashlib.sha1(CERTIFICATE).hexdigest().upper()
TOOL = r'''#!/usr/bin/env python3
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys

kind, *args = sys.argv[1:]
try:
    if kind == "plist":
        command, filename = args[1], Path(args[2])
        operation, key, *value = command.split(" ", 2)
        data = plistlib.loads(filename.read_bytes())
        keys = key.lstrip(":").split(":")
        item = data
        for key in keys[:-1]:
            item = item[int(key)] if isinstance(item, list) else item[key]
        key = int(keys[-1]) if isinstance(item, list) else keys[-1]
        if operation == "Set":
            if key not in item:
                raise KeyError(key)
            item[key] = value[0]
            filename.write_bytes(plistlib.dumps(data))
        else:
            item = item[key]
            if isinstance(item, list):
                print("Array {\n" + "\n".join(str(value) for value in item) + "\n}")
            elif isinstance(item, bool):
                print(str(item).lower())
            else:
                print(item)
    elif kind == "plutil":
        item = plistlib.loads(Path(args[-1]).read_bytes())
        for key in args[1].split("."):
            item = item[int(key)] if isinstance(item, list) else item[key]
        if isinstance(item, bytes):
            print(base64.b64encode(item).decode())
        elif isinstance(item, datetime.datetime):
            print(item.strftime("%Y-%m-%dT%H:%M:%SZ"))
        else:
            print(item)
    elif kind == "date":
        if args == ["+%s"]:
            print(int(datetime.datetime.now(datetime.timezone.utc).timestamp()))
        else:
            print(int(datetime.datetime.strptime(args[-2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()))
    elif kind == "base64":
        sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read(), validate=True))
    elif kind == "ditto":
        if os.environ.get("FAIL_COPY"):
            sys.exit(1)
        shutil.copytree(args[0], args[1], symlinks=True)
    else:
        with open(os.environ["FIXTURE_CALLS"], "a") as output:
            output.write(json.dumps([kind, *args]) + "\n")
        if kind == "xcrun" and args[0] == "vtool":
            print("platform " + os.environ.get("FIXTURE_PLATFORM", "IOS"))
        if kind == "codesign" and args[-1] == os.environ.get("FAIL_SIGN_TARGET"):
            sys.exit(1)
except (KeyError, IndexError, ValueError, OSError):
    sys.exit(1)
'''


class LiveActivityDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="atlas widget fixtures ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.calls = self.root / "calls.jsonl"
        self.tool = self.root / "fixture-tool"
        self.tool.write_text(TOOL)
        self.tool.chmod(0o755)
        tools = ["xcrun", "codesign", "ditto"]
        if sys.platform != "darwin":
            tools += ["plutil", "date", "base64"]
        for name in tools:
            wrapper = self.root / name
            wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{self.tool}" {name} "$@"\n')
            wrapper.chmod(0o755)
        self.app = self.root / "Atlas.app"
        self.activity = self.app / "PlugIns/AtlasLiveActivity.appex"
        self.activity.mkdir(parents=True)
        self.write_plist(self.app / "Info.plist", {
            "CFBundleIdentifier": "dev.tuist.atlas", "CFBundleVersion": "1792920000",
            "CFBundleShortVersionString": "0.1.0",
        })
        self.activity_plist = {
            "CFBundleIdentifier": "dev.tuist.atlas.live-activity",
            "CFBundleExecutable": "AtlasLiveActivity", "CFBundlePackageType": "XPC!",
            "CFBundleVersion": "1", "CFBundleShortVersionString": "0.0.1",
            "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
        }
        self.write_plist(self.activity / "Info.plist", self.activity_plist)
        (self.activity / "AtlasLiveActivity").write_bytes(b"fixture executable")
        (self.activity / "AtlasLiveActivity").chmod(0o755)
        self.profile = {
            "Entitlements": {
                "application-identifier": "U6LC622NKF.dev.tuist.atlas.live-activity",
                "com.apple.developer.team-identifier": "U6LC622NKF", "get-task-allow": False,
                "aps-environment": "production", "keychain-access-groups": ["U6LC622NKF.*"],
            },
            "ProvisionedDevices": ["device-one", "device-two"],
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=2),
            "DeveloperCertificates": [CERTIFICATE],
        }
        self.host_profile = self.root / "host-profile.plist"
        self.write_plist(self.host_profile, {"ProvisionedDevices": ["device-one", "device-two"]})
        self.profile_path = self.root / "activity-profile.plist"

    def write_plist(self, path, value):
        path.write_bytes(plistlib.dumps(value))

    def run_script(self, script, *args, **environment):
        setup = 'source "$1"; shift\n'
        if sys.platform != "darwin":
            setup += 'live_activity_plist() { "$FIXTURE_TOOL" plist "$@"; }\n'
        return subprocess.run(
            ["bash", "-c", "set -euo pipefail\n" + setup + script,
             "fixture", str(DIRECTORY / "live-activity.sh"), *map(str, args)],
            env={**os.environ, "PATH": f"{self.root}:{os.environ['PATH']}",
                 "FIXTURE_TOOL": str(self.tool), "FIXTURE_CALLS": str(self.calls), **environment},
            capture_output=True, text=True,
        )

    def validate_profile(self):
        self.write_plist(self.profile_path, self.profile)
        return self.run_script('validate_live_activity_profile "$1" "$2" "$3"',
                               self.profile_path, self.host_profile, IDENTITY)

    def test_profile_accepts_same_certificate_at_any_index(self):
        self.profile["DeveloperCertificates"] = [b"another certificate", CERTIFICATE]
        result = self.validate_profile()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_profile_rejects_wrong_identity_team_type_expiry_and_devices(self):
        mutations = [
            ("Entitlements", "application-identifier", "U6LC622NKF.dev.tuist.atlas"),
            ("Entitlements", "com.apple.developer.team-identifier", "OTHERTEAM"),
            ("Entitlements", "get-task-allow", True),
            (None, "ExpirationDate", datetime.datetime(2000, 1, 1)),
            (None, "ProvisionsAllDevices", True),
            (None, "ProvisionedDevices", []),
            (None, "ProvisionedDevices", "device-one"),
            (None, "ProvisionedDevices", ["device-one"]),
            (None, "DeveloperCertificates", [b"wrong certificate"]),
            (None, "DeveloperCertificates", []),
        ]
        original = plistlib.dumps(self.profile)
        for parent, key, value in mutations:
            with self.subTest(key=key, value=value):
                self.profile = plistlib.loads(original)
                (self.profile[parent] if parent else self.profile)[key] = value
                self.assertNotEqual(self.validate_profile().returncode, 0)

    def test_profile_rejects_missing_required_fields(self):
        original = plistlib.dumps(self.profile)
        for key in ["ExpirationDate", "ProvisionedDevices", "DeveloperCertificates", "Entitlements"]:
            with self.subTest(key=key):
                self.profile = plistlib.loads(original)
                del self.profile[key]
                self.assertNotEqual(self.validate_profile().returncode, 0)

    def test_bundle_checks_production_identity_executable_extension_point_and_platform(self):
        result = self.run_script('validate_live_activity_bundle "$1"', self.app)
        self.assertEqual(result.returncode, 0, result.stderr)
        for key in ["CFBundleIdentifier", "CFBundleExecutable", "CFBundlePackageType", "NSExtension"]:
            with self.subTest(key=key):
                wrong = {**self.activity_plist, key: "wrong"}
                self.write_plist(self.activity / "Info.plist", wrong)
                self.assertNotEqual(self.run_script('validate_live_activity_bundle "$1"', self.app).returncode, 0)
        self.write_plist(self.activity / "Info.plist", self.activity_plist)
        self.assertNotEqual(self.run_script('validate_live_activity_bundle "$1"', self.app,
                                            FIXTURE_PLATFORM="IOSSIMULATOR").returncode, 0)
        (self.app / "PlugIns/Other.appex").mkdir()
        self.assertNotEqual(self.run_script('validate_live_activity_bundle "$1"', self.app).returncode, 0)

    def test_preparation_stamps_copy_and_uses_only_extension_identity_entitlements(self):
        profile = self.root / "fixture.mobileprovision"
        profile.write_bytes(b"fixture profile")
        entitlements = self.root / "activity-entitlements.plist"
        result = self.run_script('prepare_live_activity_distribution "$1" "$2" "$3"',
                                 self.app, profile, entitlements)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.activity / "embedded.mobileprovision").read_bytes(), profile.read_bytes())
        plist = plistlib.loads((self.activity / "Info.plist").read_bytes())
        self.assertEqual(plist["CFBundleVersion"], "1792920000")
        self.assertEqual(plist["CFBundleShortVersionString"], "0.1.0")
        values = plistlib.loads(entitlements.read_bytes())
        self.assertEqual(values, {key: self.profile["Entitlements"][key] for key in
                                 ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow"]})

    def sign(self, **environment):
        return self.run_script('sign_live_activity_distribution "$1" "$2" "$3" "$4" "$5"',
                               self.app, "fixture-identity", self.root / "temporary keychain",
                               self.root / "host-entitlements.plist", self.root / "activity-entitlements.plist",
                               **environment)

    def test_scans_both_executables_and_signs_inside_out_with_separate_entitlements(self):
        frameworks = self.app / "Frameworks/Outer.framework/Frameworks/Inner.framework"
        frameworks.mkdir(parents=True)
        library = frameworks / "libFixture.dylib"
        library.write_bytes(b"fixture library")
        result = self.sign()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        scan = calls[0]
        self.assertEqual(scan.count("--scan-executable"), 2)
        self.assertIn(str(self.activity / "AtlasLiveActivity"), scan)
        signs = [call for call in calls if call[:2] == ["codesign", "--force"]]
        self.assertEqual([call[-1] for call in signs], [
            str(library), str(frameworks), str(self.app / "Frameworks/Outer.framework"),
            str(self.activity), str(self.app),
        ])
        self.assertIn(str(self.root / "activity-entitlements.plist"), signs[-2])
        self.assertIn(str(self.root / "host-entitlements.plist"), signs[-1])
        self.assertEqual(calls[-1], ["codesign", "--verify", "--deep", "--strict", str(self.app)])

    def test_extension_signing_failure_stops_before_host_signing(self):
        result = self.sign(FAIL_SIGN_TARGET=str(self.activity))
        self.assertNotEqual(result.returncode, 0)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertFalse(any(call[0] == "codesign" and call[-1] == str(self.app) for call in calls))

    def test_bundle_preflights_extension_profile_before_private_certificate(self):
        script = (DIRECTORY / "bundle.sh").read_text()
        self.assertLess(script.index('validate_live_activity_bundle "$app_source"'), script.index("op read"))
        self.assertLess(script.index("validate_live_activity_profile"), script.index("Distribution Certificate/distribution.p12"))

    def embed(self, source, destination, **environment):
        return subprocess.run(["bash", str(MODULES / "embed-widget.sh"), str(source), str(destination)],
                              env={**os.environ, "PATH": f"{self.root}:{os.environ['PATH']}", **environment},
                              capture_output=True, text=True)

    def test_embedding_replaces_tree_preserves_source_permissions_and_siblings(self):
        source = self.root / "built/AtlasLiveActivity.appex"
        source.parent.mkdir()
        source.mkdir()
        (source / "Info.plist").write_bytes(b"fixture plist")
        (source / "AtlasLiveActivity").write_bytes(b"new executable")
        (source / "AtlasLiveActivity").chmod(0o755)
        (self.activity / "obsolete.txt").write_text("obsolete")
        sibling = self.app / "PlugIns/Sibling.bundle"
        sibling.mkdir()
        result = self.embed(source, self.activity)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.activity / "obsolete.txt").exists())
        self.assertTrue(os.access(self.activity / "AtlasLiveActivity", os.X_OK))
        self.assertTrue(sibling.is_dir())
        self.assertEqual((source / "AtlasLiveActivity").read_bytes(), b"new executable")
        self.assertFalse(list(self.activity.parent.glob(".AtlasLiveActivity.*")))

    def test_embedding_rejects_bad_destination_self_copy_and_failed_copy_without_damage(self):
        before = (self.activity / "Info.plist").read_bytes()
        self.assertNotEqual(self.embed(self.activity, self.activity).returncode, 0)
        self.assertNotEqual(self.embed(self.activity, self.app / "AtlasLiveActivity.appex").returncode, 0)
        source = self.root / "AtlasLiveActivity.appex"
        source.mkdir()
        (source / "Info.plist").write_bytes(b"fixture")
        executable = source / "AtlasLiveActivity"
        executable.write_bytes(b"fixture")
        executable.chmod(0o755)
        self.assertNotEqual(self.embed(source, self.activity, FAIL_COPY="true").returncode, 0)
        self.assertEqual((self.activity / "Info.plist").read_bytes(), before)
        self.assertFalse(list(self.activity.parent.glob(".AtlasLiveActivity.*")))


class WidgetModuleTests(unittest.TestCase):
    def analyze(self, variant="simulator", bundle_id="dev.tuist.atlas.live-activity", sdk_digest="sdk-v1"):
        actions, writes = [], {}
        source_files = ["ios/LiveActivity/AtlasActivityAttributes.swift", "ios/LiveActivity/AtlasActivityView.swift",
                        "ios/LiveActivity/AtlasLiveActivityWidget.swift"]
        context = {"label": {"id": "Widget", "package": ""}, "build_dir": ".once/out/Widget",
                   "srcs": source_files, "attr": {"sdk_variant": variant, "bundle_id": bundle_id,
                                                 "info_plist": "ios/LiveActivity/Info.plist"}}

        def host_command(argv, **kwargs):
            if "--find" in argv:
                return "/Xcode/usr/bin/" + argv[-1]
            return "/Xcode/SDK" if "--show-sdk-path" in argv else "Swift fixture version"

        def fail(message):
            raise ValueError(message)

        namespace = {
            "host_os": lambda: "macos", "host_env": lambda key: "", "host_which": lambda name: "/usr/bin/" + name,
            "host_command": host_command, "glob": lambda paths: paths,
            "host_file_sha256": lambda path: "file-digest:" + path,
            "host_tree_sha256": lambda path: sdk_digest + path,
            "content_sha256": lambda value: hashlib.sha256(value.encode()).hexdigest(),
            "declare_output": lambda name: context["build_dir"] + "/" + name,
            "workspace_root": lambda: "/workspace",
            "host_file_read": lambda path: "$(ATLAS_ACTIVITY_BUNDLE_ID) $(ATLAS_SUPPORTED_PLATFORM) ${ATLAS_PLATFORM_NAME}",
            "write_path": lambda path, value: writes.update({path: value}),
            "run_action": lambda **kwargs: actions.append(kwargs), "fail": fail,
        }
        for name in ["target_kind", "attr", "capability", "source_reference"]:
            namespace[name] = lambda *args, **kwargs: kwargs
        exec(compile((MODULES / "widget.star").read_text(), "widget.star", "exec"), namespace)
        provider = namespace["_atlas_widget_extension_impl"](context)
        return provider, actions, writes

    def test_both_platforms_use_widget_main_extension_safe_flags_and_signed_tree_provider(self):
        for variant in ["simulator", "device"]:
            with self.subTest(variant=variant):
                provider, actions, writes = self.analyze(variant)
                argv = actions[0]["argv"]
                triple = "arm64-apple-ios17.0" + ("-simulator" if variant == "simulator" else "")
                self.assertIn(triple, argv)
                self.assertIn("-application-extension", argv)
                self.assertIn("-parse-as-library", argv)
                self.assertIn("-application_extension", argv)
                self.assertIn(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"],
                              [argv[index:index + 4] for index in range(len(argv) - 3)])
                self.assertIn(["-Xlinker", "-u", "-Xlinker", "_main"],
                              [argv[index:index + 4] for index in range(len(argv) - 3)])
                self.assertIn("@executable_path/../../Frameworks", argv)
                self.assertIn("-isysroot/Xcode/SDK", argv)
                self.assertEqual(len(actions[0]["inputs"]), 3)
                self.assertTrue(provider["application_extension"])
                self.assertEqual(actions[1]["outputs"], [provider["app_path"]])
                self.assertEqual(provider["app_files"], [provider["app_path"]])
                self.assertIn(provider["app_executable"], actions[1]["inputs"])
                self.assertNotIn("$(", next(iter(writes.values())))

    def test_sdk_content_changes_invalidate_action_and_module_cache(self):
        first = self.analyze(sdk_digest="sdk-v1")[1][0]
        second = self.analyze(sdk_digest="sdk-v2")[1][0]
        self.assertNotEqual(first["toolchain_identity"], second["toolchain_identity"])
        self.assertNotEqual(first["clean_paths"], second["clean_paths"])

    def test_preview_identity_is_supported_and_other_bundle_ids_are_rejected(self):
        bundle_id = "dev.tuist.atlas.settings-preview.live-activity"
        self.assertEqual(self.analyze(bundle_id=bundle_id)[0]["bundle_id"], bundle_id)
        with self.assertRaises(ValueError):
            self.analyze(bundle_id="dev.other.widget")


if __name__ == "__main__":
    unittest.main()
