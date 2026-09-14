import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("restore-translations.sh").resolve()
CATALOG = "server/priv/gettext/es/LC_MESSAGES/default.po"


class RestoreTranslationsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.remote = root / "remote.git"
        self.repo = root / "repo"
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.git("init", "--bare", str(self.remote), cwd=root)
        self.git("init", "-b", "main", str(self.repo), cwd=root)
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.git("remote", "add", "origin", str(self.remote))
        self.write(CATALOG, 'msgid "Hello"\nmsgstr ""\n')
        self.write("source.txt", "original\n")
        self.commit("Initial state")
        self.git("push", "origin", "main")

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env,
                              check=True, capture_output=True, text=True).stdout.strip()

    def write(self, path, content):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-m", message)

    def checkpoint(self):
        self.git("checkout", "-b", "l10n/update-translations")
        self.write(CATALOG, 'msgid "Hello"\nmsgstr "Hola"\n')
        self.write(".l10n/default.lock", "completed\n")
        self.write("source.txt", "must not be restored\n")
        self.commit("Partial translations")
        self.git("push", "origin", "l10n/update-translations")
        self.git("checkout", "main")

    def restore(self):
        return subprocess.run(["bash", str(SCRIPT)], cwd=self.repo, env=self.env,
                              capture_output=True, text=True)

    def test_first_run_without_checkpoint(self):
        self.assertEqual(self.restore().returncode, 0)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_unmerged_translations_survive_a_fresh_checkout(self):
        self.checkpoint()
        self.write("source.txt", "new main content\n")
        self.commit("New source")
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('msgstr "Hola"', (self.repo / CATALOG).read_text())
        self.assertTrue((self.repo / ".l10n/default.lock").exists())
        self.assertEqual((self.repo / "source.txt").read_text(), "new main content\n")

    def test_conflicting_main_translation_stops_before_spending(self):
        self.checkpoint()
        self.write(CATALOG, 'msgid "Hello"\nmsgstr "Buenos dias"\n')
        self.commit("Reviewed main translation")
        self.assertNotEqual(self.restore().returncode, 0)

    def test_merged_checkpoint_does_not_revert_new_main_translation(self):
        self.checkpoint()
        self.git("merge", "--no-edit", "l10n/update-translations")
        self.write(CATALOG, 'msgid "Hello"\nmsgstr "Buenos dias"\n')
        self.commit("Reviewed main translation")
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('msgstr "Buenos dias"', (self.repo / CATALOG).read_text())


if __name__ == "__main__":
    unittest.main()
