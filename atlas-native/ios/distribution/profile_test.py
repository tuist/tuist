import copy
import datetime
import hashlib
import unittest

from profile import BUNDLE_ID, TEAM_ID, signing_inputs


class SigningInputsTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 10, 1, tzinfo=datetime.timezone.utc)
        self.certificate = b"fixture distribution certificate"
        self.fingerprint = hashlib.sha1(self.certificate).hexdigest().upper()
        self.identities = f'  1) {self.fingerprint} "Apple Distribution: Tuist GmbH ({TEAM_ID})"'
        self.profile = {
            "ExpirationDate": datetime.datetime(2027, 1, 1),
            "TeamIdentifier": [TEAM_ID],
            "ApplicationIdentifierPrefix": [TEAM_ID],
            "ProvisionedDevices": ["fixture-udid"],
            "DeveloperCertificates": [self.certificate],
            "Entitlements": {
                "get-task-allow": False,
                "application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
                "com.apple.developer.team-identifier": TEAM_ID,
                "keychain-access-groups": [f"{TEAM_ID}.*"],
            },
        }
        self.info = {
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleExecutable": "Atlas",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "DTPlatformName": "iphoneos",
        }

    def inputs(self):
        return signing_inputs(self.profile, self.info, self.identities, self.now)

    def test_derives_device_identity_and_keychain_from_profile(self):
        identity, entitlements = self.inputs()
        self.assertEqual(identity, self.fingerprint)
        self.assertEqual(entitlements, {
            "application-identifier": f"{TEAM_ID}.{BUNDLE_ID}",
            "com.apple.developer.team-identifier": TEAM_ID,
            "keychain-access-groups": [f"{TEAM_ID}.{BUNDLE_ID}"],
            "get-task-allow": False,
        })

    def test_supports_legacy_application_prefix_distinct_from_team(self):
        self.profile["ApplicationIdentifierPrefix"] = ["LEGACYPREF"]
        self.profile["Entitlements"]["application-identifier"] = f"LEGACYPREF.{BUNDLE_ID}"
        self.profile["Entitlements"]["keychain-access-groups"] = ["LEGACYPREF.*"]
        _, entitlements = self.inputs()
        self.assertEqual(entitlements["keychain-access-groups"], [f"LEGACYPREF.{BUNDLE_ID}"])
        self.assertEqual(entitlements["com.apple.developer.team-identifier"], TEAM_ID)

    def test_rejects_expired_wrong_team_store_and_enterprise_profiles(self):
        for field, value in [
            ("ExpirationDate", datetime.datetime(2025, 1, 1)),
            ("TeamIdentifier", ["OTHERTEAM"]),
            ("ProvisionedDevices", []),
            ("ProvisionsAllDevices", True),
        ]:
            with self.subTest(field=field):
                original = copy.deepcopy(self.profile)
                self.profile[field] = value
                with self.assertRaises(ValueError):
                    self.inputs()
                self.profile = original

    def test_rejects_development_wrong_app_wildcard_and_keychain_mismatch(self):
        for field, value in [
            ("get-task-allow", True),
            ("application-identifier", f"{TEAM_ID}.dev.tuist.app"),
            ("application-identifier", f"{TEAM_ID}.*"),
            ("com.apple.developer.team-identifier", "OTHERTEAM"),
            ("keychain-access-groups", ["OTHERTEAM.*"]),
        ]:
            with self.subTest(field=field):
                original = copy.deepcopy(self.profile)
                self.profile["Entitlements"][field] = value
                with self.assertRaises(ValueError):
                    self.inputs()
                self.profile = original

    def test_rejects_missing_or_non_distribution_identity(self):
        for identities in ["", self.identities.replace(self.fingerprint, "0" * 40),
                           self.identities.replace("Apple Distribution:", "Apple Development:")]:
            with self.subTest(identities=identities):
                self.identities = identities
                with self.assertRaises(ValueError):
                    self.inputs()

    def test_rejects_simulator_or_fixture_apps(self):
        for field, value in [
            ("CFBundleSupportedPlatforms", ["iPhoneSimulator"]),
            ("DTPlatformName", "iphonesimulator"),
            ("CFBundleIdentifier", "dev.tuist.atlas.settings-preview"),
        ]:
            with self.subTest(field=field):
                original = self.info.copy()
                self.info[field] = value
                with self.assertRaises(ValueError):
                    self.inputs()
                self.info = original


if __name__ == "__main__":
    unittest.main()
