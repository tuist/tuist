#!/usr/bin/env python3
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("benchmark", pathlib.Path(__file__).with_name("server-elixir-cache-benchmark.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkTest(unittest.TestCase):
    source = 'tuist: [project: "tuist/server", cache: true]'

    def test_remote_configuration_does_not_disable_remote_or_filter_dependencies(self):
        config = benchmark.cache_config(self.source, "remote", pathlib.Path("/tmp/cache"))
        self.assertIn("upload: false", config)
        for option in ("remote: false", "dependencies:", "exclude:", "builders:"):
            self.assertNotIn(option, config)
        self.assertIn("upload: true", benchmark.cache_config(self.source, "seed", pathlib.Path("/tmp/cache")))
        self.assertIn("cache: false", benchmark.cache_config(self.source, "disabled", pathlib.Path("/tmp/cache")))
        with self.assertRaises(ValueError):
            benchmark.cache_config("different source", "remote", pathlib.Path("/tmp/cache"))

    def test_already_current_is_not_a_keyed_restore(self):
        events = [dict(outcome="local_hit", key="", reason="up_to_date"), dict(outcome="remote_hit", key="key", reason="", read_bytes=42, read_duration_us=7)]
        result = benchmark.summarize(events)
        self.assertEqual(result["keyed_local_hits"], 0)
        self.assertEqual(result["remote_hits"], 1)
        self.assertEqual(result["up_to_date"], 1)
        self.assertEqual(result["remote_read_bytes"], 42)

    def test_incomplete_sigterm_exit_zero_is_not_success(self):
        with self.assertRaises(RuntimeError):
            benchmark.validate(dict(status=0, completed=False))

    def test_missing_remote_hits_or_local_contamination_fail(self):
        sample = dict(status=0, completed=True, mode="remote", remote_hits=1, keyed_local_hits=0, local_entries_before=0)
        benchmark.validate(sample)
        for change in [dict(remote_hits=0), dict(keyed_local_hits=1), dict(local_entries_before=1)]:
            with self.assertRaises(RuntimeError):
                benchmark.validate(sample | change)
        with self.assertRaises(RuntimeError):
            benchmark.validate(dict(status=0, completed=True, mode="seed", remote_writes=0))

    def test_compilation_messages_are_deduplicated(self):
        self.assertEqual(benchmark.compiled_apps("Generated alpha app\n===> Compiling beta\nGenerated alpha app\n"), ["alpha", "beta"])

    def test_each_sample_resets_sources_builds_and_local_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            checkout = root / "checkout"
            server = checkout / "server"
            (server / "deps/package").mkdir(parents=True)
            (server / "deps/package/original").write_text("original")
            (server / "mix.exs").write_text(self.source)
            (server / "mix.lock").write_text("locked")
            temp = root / "temp"
            temp.mkdir()
            modes = []

            class FakeProcess:
                pid = 123

                def __init__(self, command, cwd, env, stdout, **kwargs):
                    self.result = pathlib.Path(env["BENCH_RESULT"])
                    self.events = pathlib.Path(env["BENCH_EVENTS"])
                    mode = self.result.stem.split("-", 1)[1]
                    modes.append(mode)
                    self.mode = mode
                    assert not (server / "deps/package/generated").exists()
                    assert not (server / "_build").exists()
                    assert not (temp / "elixir-cache-benchmark/local-artifacts").exists()
                    assert (server / "deps/package/original").read_text() == "original"
                    (server / "deps/package/generated").touch()
                    (server / "_build").mkdir()
                    (temp / "elixir-cache-benchmark/local-artifacts").mkdir()
                    stdout.write("Generated package app\nGenerated tuist app\n")

                def wait(self, timeout):
                    self.result.write_text(json.dumps(dict(completed=True, phases_ms={})))
                    events = [] if self.mode == "disabled" else [dict(outcome="miss" if self.mode == "seed" else "remote_hit", reason="", key="key", write_source="remote" if self.mode == "seed" else "")]
                    self.events.write_text(json.dumps(dict(dependency_cache=events)))
                    return 0

            with patch.dict(os.environ, GITHUB_ACTIONS="true", GITHUB_WORKSPACE=str(checkout), RUNNER_TEMP=str(temp), GITHUB_SHA="commit"), patch.object(benchmark.subprocess, "Popen", FakeProcess), patch.object(benchmark.platform, "platform", return_value="test-linux"), patch("builtins.print"):
                benchmark.main()
            self.assertEqual(modes, ["seed", "disabled", "remote", "remote", "disabled"])
            self.assertEqual((server / "mix.exs").read_text(), self.source)
            self.assertFalse((temp / "elixir-cache-benchmark/pristine-deps").exists())
            samples = json.loads((temp / "elixir-cache-benchmark/samples.json").read_text())
            self.assertEqual(len(samples), 5)
            self.assertTrue(all(sample["local_entries_before"] == 0 for sample in samples))


if __name__ == "__main__":
    unittest.main()
