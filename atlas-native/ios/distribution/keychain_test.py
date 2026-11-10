"""Exercise disposable signing-keychain setup without credentials or macOS state."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class SigningKeychainTests(unittest.TestCase):
    def run_keychain(self, original, fail_command="", fail_list=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state.json"
            state.write_text(json.dumps({"search_list": original, "calls": []}))
            security = root / "security"
            security.write_text("""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

state = Path(os.environ["KEYCHAIN_TEST_STATE"])
data = json.loads(state.read_text())
args = sys.argv[1:]
data["calls"].append(args)
failed = args[0] == os.environ["KEYCHAIN_TEST_FAIL_COMMAND"]
if args == ["list-keychains", "-d", "user"]:
    failed = os.environ["KEYCHAIN_TEST_FAIL_LIST"] == "true"
    if not failed:
        for keychain in data["search_list"]:
            print(f'    "{keychain}"')
elif args[:4] == ["list-keychains", "-d", "user", "-s"]:
    data["search_list"] = args[4:]
state.write_text(json.dumps(data))
sys.exit(1 if failed else 0)
""")
            security.chmod(0o755)
            result = subprocess.run([
                "bash", "-c", """
set -euo pipefail
source "$1"
keychain='/tmp/Atlas Signing/signing.keychain-db'
trap 'delete_signing_keychain "$keychain"' EXIT
create_signing_keychain "$keychain" password
security import certificate.p12
""", "test", str(Path(__file__).with_name("keychain.sh")),
            ], env={
                **os.environ,
                "PATH": f"{root}:{os.environ['PATH']}",
                "KEYCHAIN_TEST_STATE": str(state),
                "KEYCHAIN_TEST_FAIL_COMMAND": fail_command,
                "KEYCHAIN_TEST_FAIL_LIST": str(fail_list).lower(),
            }, capture_output=True, text=True)
            return result, json.loads(state.read_text())

    def test_adds_signing_keychain_and_restores_original_order(self):
        original = ["/Users/runner/Library/Keychains/login.keychain-db",
                    "/tmp/Another Keychain/build.keychain-db"]
        result, state = self.run_keychain(original)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["search_list"], original)
        updates = [call for call in state["calls"] if call[:4] ==
                   ["list-keychains", "-d", "user", "-s"]]
        self.assertEqual(updates, [
            ["list-keychains", "-d", "user", "-s",
             "/tmp/Atlas Signing/signing.keychain-db", *original],
            ["list-keychains", "-d", "user", "-s", *original],
        ])
        self.assertEqual(state["calls"][-1],
                         ["delete-keychain", "/tmp/Atlas Signing/signing.keychain-db"])

    def test_restores_empty_search_list(self):
        result, state = self.run_keychain([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["search_list"], [])

    def test_restores_search_list_when_import_fails(self):
        original = ["/tmp/login.keychain-db"]
        result, state = self.run_keychain(original, fail_command="import")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["search_list"], original)
        self.assertEqual(state["calls"][-1][0], "delete-keychain")

    def test_restores_search_list_when_setup_fails(self):
        original = ["/tmp/login.keychain-db"]
        result, state = self.run_keychain(original, fail_command="unlock-keychain")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["search_list"], original)
        self.assertFalse(any(call[0] == "import" for call in state["calls"]))

    def test_does_not_delete_keychain_when_creation_fails(self):
        original = ["/tmp/login.keychain-db"]
        result, state = self.run_keychain(original, fail_command="create-keychain")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["search_list"], original)
        self.assertFalse(any(call[0] == "delete-keychain" for call in state["calls"]))

    def test_does_not_replace_search_list_when_snapshot_fails(self):
        original = ["/tmp/login.keychain-db"]
        result, state = self.run_keychain(original, fail_list=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(state["search_list"], original)
        self.assertFalse(any(call[0] == "create-keychain" for call in state["calls"]))
        self.assertFalse(any("-s" in call for call in state["calls"]))
        self.assertFalse(any(call[0] == "delete-keychain" for call in state["calls"]))


if __name__ == "__main__":
    unittest.main()
