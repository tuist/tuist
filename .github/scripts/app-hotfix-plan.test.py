#!/usr/bin/env python3
"""Credential-free hotfix planning checks against real disposable Git history."""

import pathlib
import subprocess
import tempfile
import time
import unittest


SCRIPT = pathlib.Path(__file__).resolve().with_name("app-hotfix-plan.py")


class HotfixPlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("commit", "--quiet", "--allow-empty", "-m", "Stable")
        self.base = self.git("rev-parse", "HEAD")
        self.git("tag", "app@0.27.1")
        self.git("commit", "--quiet", "--allow-empty", "-m", "TLS backport")
        self.source = self.git("rev-parse", "HEAD")
        self.feed = self.root / "appcast.xml"
        self.write_feed()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL).strip()

    def write_feed(self, version="0.27.1", build=1791997442, url=None):
        url = url or f"https://github.com/tuist/tuist/releases/download/app@{version}/Tuist.dmg"
        self.feed.write_text(f"""<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item><sparkle:shortVersionString>{version}</sparkle:shortVersionString>
          <sparkle:version>{build}</sparkle:version><enclosure url="{url}"/></item>
          <item><sparkle:shortVersionString>0.20.2</sparkle:shortVersionString>
          <sparkle:version>0.20.2</sparkle:version></item></channel></rss>""")

    def run_plan(self, tag="app@0.27.1", source=None):
        return subprocess.run(
            ["python3", str(SCRIPT), "--", tag, source or self.source, str(self.feed)],
            cwd=self.root, text=True, capture_output=True,
        )

    def assert_rejected(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("app-should-release=true", result.stdout)

    def test_plans_patch_not_main_minor_and_keeps_immutable_source(self):
        result = self.run_plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        outputs = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(outputs["app-next-version"], "app@0.27.2")
        self.assertEqual(outputs["app-next-version-number"], "0.27.2")
        self.assertEqual(outputs["source-sha"], self.source)
        self.assertEqual(outputs["app-should-release"], "true")
        self.assertGreater(int(outputs["build-number"]), 1791997442)

    def test_rejects_mutable_refs_and_expression_or_option_inputs(self):
        for source in ["main", self.source[:12], "--help", "${{ secrets.TOKEN }}", self.source + "\nfoo=bar"]:
            with self.subTest(source=source):
                self.assert_rejected(self.run_plan(source=source))
        for tag in ["main", "app@0.27.1^", "app@00.27.1", "app@0.27.1\nfoo=bar"]:
            with self.subTest(tag=tag):
                self.assert_rejected(self.run_plan(tag=tag))

    def test_rejects_unchanged_and_unrelated_sources(self):
        self.assert_rejected(self.run_plan(source=self.base))
        self.git("switch", "--orphan", "unrelated")
        self.git("commit", "--quiet", "--allow-empty", "-m", "Other product")
        self.assert_rejected(self.run_plan(source=self.git("rev-parse", "HEAD")))

    def test_rejects_existing_patch_tag_instead_of_replacing_contents(self):
        self.git("tag", "app@0.27.2", self.source)
        self.assert_rejected(self.run_plan())

    def test_rejects_stale_baseline_even_if_old_item_remains_in_feed(self):
        self.write_feed(version="0.28.0")
        self.assert_rejected(self.run_plan())
        self.write_feed(version="0.26.9")
        self.assert_rejected(self.run_plan())

    def test_rejects_future_or_non_numeric_live_build(self):
        self.write_feed(build=int(time.time()) + 600)
        self.assert_rejected(self.run_plan())
        self.write_feed(build="not-a-build")
        self.assert_rejected(self.run_plan())

    def test_rejects_empty_malformed_or_wrong_payload_feed(self):
        for contents in ["<rss><channel/></rss>", "not XML", "<rss><channel><item/></channel></rss>"]:
            with self.subTest(contents=contents):
                self.feed.write_text(contents)
                self.assert_rejected(self.run_plan())
        self.write_feed(url="https://example.invalid/main/Tuist.dmg")
        self.assert_rejected(self.run_plan())


if __name__ == "__main__":
    unittest.main()
