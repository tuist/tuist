import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

from publish import git, publish


class PublishTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / "remote.git"
        subprocess.run(["git", "init", "--bare", "--initial-branch=main", str(self.remote)], check=True, capture_output=True)
        self.repo = self.clone("distribution")
        git(self.repo, "config", "user.name", "test")
        git(self.repo, "config", "user.email", "test@example.com")
        (self.repo / "obsolete").write_text("bootstrap")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-m", "Initial commit")
        git(self.repo, "push", "origin", "main")
        self.package = self.root / "package"
        self.package.mkdir()
        self.source = "a" * 40
        (self.package / "SOURCE_COMMIT").write_text(self.source + "\n")
        (self.package / "README.md").write_text("Integration")
        (self.package / "hooks").mkdir()
        (self.package / "hooks/pre-command").write_text("#!/bin/sh\nexit 0\n")

    def clone(self, name):
        checkout = self.root / name
        subprocess.run(["git", "clone", str(self.remote), str(checkout)], check=True, capture_output=True)
        return checkout

    def release(self, version="v1.0.0", repo=None):
        with contextlib.redirect_stdout(io.StringIO()):
            publish(self.package, repo or self.repo, version, self.source)

    def test_publish_tags_main_and_restores_executable_bit(self):
        self.release()
        commit = git(self.remote, "rev-parse", "main")
        self.assertEqual(git(self.remote, "rev-parse", "v1.0.0"), commit)
        self.assertEqual(git(self.remote, "rev-parse", "v1"), commit)
        self.assertTrue(git(self.remote, "ls-tree", "main", "hooks/pre-command").startswith("100755"))
        self.assertEqual(git(self.remote, "ls-tree", "main", "obsolete"), "")

    def test_retry_of_partial_coordinated_release_is_idempotent(self):
        self.release()
        commit = git(self.remote, "rev-parse", "main")
        self.release(repo=self.clone("retry"))
        self.assertEqual(git(self.remote, "rev-parse", "main"), commit)

    def test_immutable_release_rejects_different_content_even_with_same_source(self):
        self.release()
        commit = git(self.remote, "rev-parse", "v1.0.0")
        (self.package / "README.md").write_text("Different")
        with self.assertRaisesRegex(ValueError, "Immutable release"):
            self.release(repo=self.clone("retry"))
        self.assertEqual(git(self.remote, "rev-parse", "v1.0.0"), commit)

    def test_retry_of_old_version_never_rolls_back_major_alias(self):
        self.release()
        (self.package / "README.md").write_text("New version")
        self.release("v1.0.1")
        new_commit = git(self.remote, "rev-parse", "v1")
        (self.package / "README.md").write_text("Integration")
        self.release(repo=self.clone("retry"))
        self.assertEqual(git(self.remote, "rev-parse", "v1"), new_commit)

    def test_rejects_new_tag_behind_latest_release(self):
        self.release("v1.0.2")
        with self.assertRaisesRegex(ValueError, "newer release"):
            self.release("v1.0.1")

    def test_new_major_preserves_previous_major_alias(self):
        self.release()
        previous = git(self.remote, "rev-parse", "v1")
        self.release("v2.0.0")
        self.assertEqual(git(self.remote, "rev-parse", "v1"), previous)
        self.assertEqual(git(self.remote, "rev-parse", "v2"), git(self.remote, "rev-parse", "v2.0.0"))

    def test_package_must_match_source_and_version_must_be_stable(self):
        (self.package / "SOURCE_COMMIT").write_text("b" * 40)
        with self.assertRaisesRegex(ValueError, "source commit"):
            self.release()
        with self.assertRaisesRegex(ValueError, "stable"):
            self.release("v1;echo unexpected")

    def test_rejected_tag_push_does_not_partially_update_remote(self):
        before = git(self.remote, "rev-parse", "main")
        hook = self.remote / "hooks/update"
        hook.write_text('#!/bin/sh\n[ "$1" != refs/tags/v1 ]\n')
        hook.chmod(0o755)
        with self.assertRaises(subprocess.CalledProcessError):
            self.release()
        self.assertEqual(git(self.remote, "rev-parse", "main"), before)
        self.assertEqual(git(self.remote, "tag", "--list"), "")
        hook.unlink()
        self.release(repo=self.clone("retry"))
        self.assertEqual(git(self.remote, "rev-parse", "main"), git(self.remote, "rev-parse", "v1"))

    def test_gitlab_package_is_self_contained(self):
        package = self.root / "gitlab-package"
        subprocess.run(["bash", str(Path(__file__).parent / "gitlab/package.sh"), str(package)], check=True)
        self.assertEqual({p.name for p in package.iterdir()}, {"cache-volume.yml", "README.md", "LICENSE.md", "SOURCE_COMMIT"})
        self.assertEqual((package / "SOURCE_COMMIT").read_text().strip(), git(Path(__file__).parent, "rev-parse", "HEAD"))


if __name__ == "__main__":
    unittest.main()
