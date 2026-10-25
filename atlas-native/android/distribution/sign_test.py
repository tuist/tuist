#!/usr/bin/env python3
"""Credential-free publication orchestration tests; tools and signing material are fake."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("sign.sh")
FINGERPRINT = ":".join(["AB"] * 32)


class SigningTests(unittest.TestCase):
    def run_signer(self, fingerprint=FINGERPRINT, debug=False, verify_exit=0, missing_ref=False):
        with tempfile.TemporaryDirectory(prefix="atlas android signing ") as directory:
            root = Path(directory)
            tools = root / "sdk" / "build-tools" / "35.0.0"
            tools.mkdir(parents=True)
            log = root / "calls"
            op = root / "op"
            op.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$4" >> "$ATLAS_TEST_LOG"
printf 'fake signing material' > "$4"
''')
            signer = tools / "apksigner"
            signer.write_text('''#!/usr/bin/env bash
set -eu
if [[ "$1" == sign ]]; then
    store= key=
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == --ks-pass ]]; then store="$2"; fi
        if [[ "$1" == --key-pass ]]; then key="$2"; fi
        if [[ "$1" == --out ]]; then
            [[ -n "$store" && "$store" != "$key" ]]
            cmp "${store#file:}" "${key#file:}"
            printf signed > "$2"; exit 0
        fi
        shift
    done
    exit 1
fi
printf 'Signer #1 certificate SHA-256 digest: %s\\n' "${ATLAS_TEST_DIGEST}"
printf 'Signer #1 certificate DN: CN=%s\\n' "${ATLAS_TEST_SUBJECT}"
exit "$ATLAS_TEST_VERIFY_EXIT"
''')
            for tool in (op, signer):
                tool.chmod(0o700)
            source = root / "input.apk"
            source.write_bytes(b"fake APK")
            output = root / "output.apk"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       ANDROID_HOME=str(root / "sdk"), ATLAS_ANDROID_KEYSTORE_REF="op://test/key",
                       ATLAS_ANDROID_KEYSTORE_PASSWORD_REF="op://test/password", ATLAS_ANDROID_KEY_ALIAS="atlas",
                       ATLAS_ANDROID_APP_LINK_SHA256=fingerprint, ATLAS_TEST_LOG=str(log),
                       ATLAS_TEST_DIGEST="ab" * 32, ATLAS_TEST_SUBJECT="Android Debug" if debug else "Atlas fixture",
                       ATLAS_TEST_VERIFY_EXIT=str(verify_exit))
            if missing_ref:
                env.pop("ATLAS_ANDROID_KEYSTORE_REF")
            result = subprocess.run(["bash", str(SCRIPT), str(source), str(output)], env=env,
                                    capture_output=True, text=True, check=False)
            fetched = log.read_text().splitlines() if log.exists() else []
            for path in fetched:
                self.assertFalse(Path(path).exists(), "Temporary signing material leaked")
            self.assertNotIn("fake signing material", result.stdout + result.stderr)
            return result, output.exists(), fetched

    def test_matching_stable_key_publishes_only_verified_output(self):
        result, published, fetched = self.run_signer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(published)
        self.assertEqual(len(fetched), 2)

    def test_rotation_accepts_a_matching_trusted_certificate(self):
        result, published, _ = self.run_signer(":".join(["CD"] * 32) + ", " + FINGERPRINT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(published)

    def test_wrong_key_debug_key_or_verification_failure_never_publish(self):
        for options in [dict(fingerprint=":".join(["CD"] * 32)), dict(debug=True), dict(verify_exit=1)]:
            with self.subTest(options=options):
                result, published, _ = self.run_signer(**options)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(published)

    def test_missing_configuration_never_fetches_credentials(self):
        result, published, fetched = self.run_signer(missing_ref=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(published)
        self.assertEqual(fetched, [])

    def test_server_incompatible_fingerprints_never_fetch_credentials(self):
        for value in [FINGERPRINT.lower(), "AB" * 32, "invalid", FINGERPRINT + ",", FINGERPRINT + "\njunk"]:
            with self.subTest(value=value):
                result, published, fetched = self.run_signer(fingerprint=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(published)
                self.assertEqual(fetched, [])


if __name__ == "__main__":
    unittest.main()
