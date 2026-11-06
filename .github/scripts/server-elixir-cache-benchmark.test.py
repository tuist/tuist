#!/usr/bin/env python3
import importlib.util
import itertools
import json
import os
import pathlib
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, call, patch

spec = importlib.util.spec_from_file_location("benchmark", pathlib.Path(__file__).with_name("server-elixir-cache-benchmark.py"))
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class BenchmarkTest(unittest.TestCase):
    source = 'tuist: [project: "tuist/server", cache: true]'

    def test_remote_configuration_is_unfiltered_and_run_scoped(self):
        for mode in ("remote", "seed"):
            config = benchmark.cache_config(self.source, mode, pathlib.Path("/tmp/cache"))
            self.assertIn('env: ["TUIST_ELIXIR_CACHE_BENCHMARK_RUN"]', config)
            self.assertIn(f"upload: {str(mode == 'seed').lower()}", config)
            for option in ("remote: false", "dependencies:", "exclude:", "builders:"):
                self.assertNotIn(option, config)
        self.assertIn("cache: false", benchmark.cache_config(self.source, "disabled", pathlib.Path("/tmp/cache")))
        for source, mode in [("different source", "remote"), (self.source, "unknown")]:
            with self.assertRaises(ValueError):
                benchmark.cache_config(source, mode, pathlib.Path("/tmp/cache"))

    def test_endpoint_metadata_never_contains_credentials_paths_or_queries(self):
        self.assertEqual(benchmark.endpoint_origin("https://user:password@cache.example:444/secret?token=secret#secret"), "https://cache.example:444")
        self.assertEqual(benchmark.endpoint_origin("http://[::1]:4000"), "http://[::1]:4000")
        self.assertEqual(benchmark.endpoint_origin(None), "account discovery")
        for endpoint in ("not a url", "https://host:invalid", "https://["):
            self.assertEqual(benchmark.endpoint_origin(endpoint), "invalid endpoint override")

    def test_already_current_is_not_a_keyed_restore(self):
        events = [dict(outcome="local_hit", key="", reason="up_to_date"), dict(outcome="remote_hit", key="key", reason="", read_bytes=42, read_duration_us=7)]
        result = benchmark.summarize(events)
        self.assertEqual(result["keyed_local_hits"], 0)
        self.assertEqual(result["remote_hits"], 1)
        self.assertEqual(result["up_to_date"], 1)
        self.assertEqual(result["remote_read_bytes"], 42)
        self.assertFalse(result["degraded"])

    def test_partial_coverage_identifies_seeded_and_unseeded_misses(self):
        result = benchmark.summarize([
            dict(outcome="remote_hit", key="hit", reason=""),
            dict(outcome="miss", key="seeded", reason=""),
            dict(outcome="miss", key="changed-bootstrap", reason=""),
        ], {"hit", "seeded"})
        self.assertTrue(result["degraded"])
        self.assertEqual(result["seeded_key_misses"], ["seeded"])
        self.assertEqual(result["remote_available_keys"], ["hit"])

    def test_incomplete_sigterm_exit_zero_is_not_success(self):
        with self.assertRaises(RuntimeError):
            benchmark.validate(dict(status=0, completed=False))

    def test_missing_remote_hits_or_local_contamination_fail(self):
        sample = dict(status=0, completed=True, mode="remote", remote_hits=1, keyed_local_hits=0)
        benchmark.validate(sample)
        for change in [dict(remote_hits=0), dict(keyed_local_hits=1), dict(record_errors=["corrupt record"])]:
            with self.assertRaises(RuntimeError):
                benchmark.validate(sample | change)
        with self.assertRaises(RuntimeError):
            benchmark.validate(sample | dict(mode="seed", remote_writes=0))
        with self.assertRaises(RuntimeError):
            benchmark.validate(sample | dict(mode="disabled", outcomes={"remote_hit": 1}))

    def test_compilation_messages_include_partitioned_dependencies(self):
        log = "Generated alpha app\n===> Compiling beta\n1> Generated jason app\n2> ===> Compiling ranch\nGenerated alpha app\n"
        self.assertEqual(benchmark.compiled_apps(log), ["alpha", "beta", "jason", "ranch"])

    def test_corrupt_records_are_preserved_as_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "sample.json"
            for data in ('{"incomplete":', '[]'):
                path.write_text(data)
                errors = []
                self.assertEqual(benchmark.read_record(path, errors), {})
                self.assertEqual(errors, ["sample.json: ValueError"] if data == '[]' else ["sample.json: JSONDecodeError"])

    def test_each_sample_resets_sources_builds_and_local_artifacts(self):
        self.run_fixture()

    def test_lock_mutation_is_rejected_after_preserving_sample(self):
        self.run_fixture(lock_change=True, expected_error=RuntimeError, expected_samples=1)

    def test_keyboard_interrupt_terminates_child_and_preserves_attempt(self):
        self.run_fixture(interruption=KeyboardInterrupt(), expected_error=KeyboardInterrupt, expected_samples=1)

    def test_timeout_terminates_child_and_preserves_attempt(self):
        self.run_fixture(interruption=subprocess.TimeoutExpired("elixir", 1), expected_error=subprocess.TimeoutExpired, expected_samples=1)

    def test_total_deadline_reduces_later_sample_budgets(self):
        with patch.object(benchmark, "TOTAL_TIMEOUT", 100), patch.object(benchmark.time, "monotonic", side_effect=itertools.count()):
            timeouts = self.run_fixture()
        self.assertTrue(all(timeout <= 100 for timeout in timeouts))
        self.assertEqual(timeouts, sorted(timeouts, reverse=True))
        self.assertLess(timeouts[-1], timeouts[0])

    def test_setup_time_consumes_total_job_budget(self):
        with patch.object(benchmark, "TOTAL_TIMEOUT", 200):
            timeouts = self.run_fixture(setup_elapsed=100)
        self.assertTrue(all(timeout <= 100 for timeout in timeouts))

    def test_deterministic_options_apply_to_and_label_every_sample(self):
        self.run_fixture(compilation="deterministic")

    def test_seeded_misses_fail_after_preserving_all_comparisons(self):
        self.run_fixture(degraded="same-key", expected_error=RuntimeError)

    def test_seeded_dependency_key_drift_still_fails(self):
        self.run_fixture(degraded="key-drift", expected_error=RuntimeError)

    def test_seeded_dependency_bypass_still_fails(self):
        self.run_fixture(degraded="bypass", expected_error=RuntimeError)

    def test_unresponsive_child_group_is_killed_after_grace_period(self):
        process = Mock(pid=123)
        process.wait.side_effect = [subprocess.TimeoutExpired("elixir", 3), 0]
        handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
        with patch.object(benchmark.os, "killpg") as killpg:
            benchmark.terminate(process)
        self.assertEqual(killpg.call_args_list, [call(123, signal.SIGTERM), call(123, signal.SIGKILL)])
        self.assertEqual({sig: signal.getsignal(sig) for sig in handlers}, handlers)

    def test_launch_failure_is_retained_as_an_incomplete_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with patch.object(benchmark.subprocess, "Popen", side_effect=FileNotFoundError()), patch("builtins.print"):
                sample, error = benchmark.measure(root, root, {}, 0, "seed", 10, set())
            self.assertIsInstance(error, FileNotFoundError)
            self.assertTrue(sample["interrupted"])
            self.assertFalse(sample["completed"])

    def test_sigterm_uses_the_interruption_cleanup_path(self):
        with self.assertRaisesRegex(KeyboardInterrupt, "SIGTERM"):
            benchmark.raise_interruption(signal.SIGTERM, None)

    def run_fixture(self, *, interruption=None, lock_change=False, degraded=False, setup_elapsed=0, expected_error=None, expected_samples=5, compilation="default"):
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
            timeouts = []

            class FakeProcess:
                pid = 123

                def __init__(self, command, cwd, env, stdout, **kwargs):
                    self.result = pathlib.Path(env["BENCH_RESULT"])
                    self.events = pathlib.Path(env["BENCH_EVENTS"])
                    self.mode = self.result.stem.split("-", 1)[1]
                    self.waits = 0
                    modes.append(self.mode)
                    assert env["TUIST_ELIXIR_CACHE_BENCHMARK_RUN"] == "123-2"
                    assert env["TUIST_ELIXIR_CACHE_BENCHMARK_COMPILATION"] == compilation
                    assert env["ERL_COMPILER_OPTIONS"] == ("[deterministic]" if compilation == "deterministic" else "")
                    assert not (server / "deps/package/generated").exists()
                    for package in ("server", "tuist_ex", "noora", "tuist_common"):
                        assert not (checkout / package / "_build").exists()
                        (checkout / package / "_build").mkdir(parents=True)
                    assert not (temp / "elixir-cache-benchmark/local-artifacts").exists()
                    assert (server / "deps/package/original").read_text() == "original"
                    (server / "deps/package/generated").touch()
                    (temp / "elixir-cache-benchmark/local-artifacts").mkdir()
                    stdout.write("1> Generated package app\nGenerated tuist app\n")

                def wait(self, timeout=None):
                    self.waits += 1
                    if self.waits > 1:
                        return 0
                    timeouts.append(timeout)
                    if interruption is not None:
                        self.result.write_text('{"phases_ms":')
                        raise interruption
                    self.result.write_text(json.dumps(dict(completed=True, phases_ms={})))
                    events = [] if self.mode == "disabled" else [dict(dependency="package", outcome="miss" if self.mode == "seed" else "remote_hit", reason="", key="key", write_source="remote" if self.mode == "seed" else "")]
                    if degraded and self.mode == "remote":
                        events[0].update(dependency="other", key="other-key")
                        events.append(dict(dependency="package", outcome="bypass" if degraded == "bypass" else "miss", reason="", key="key" if degraded == "same-key" else "drifted-key"))
                    self.events.write_text(json.dumps(dict(dependency_cache=events)))
                    if lock_change:
                        (server / "mix.lock").write_text("changed")
                    return 0

            handler = signal.getsignal(signal.SIGTERM)
            with patch.dict(os.environ, GITHUB_ACTIONS="true", GITHUB_WORKSPACE=str(checkout), RUNNER_TEMP=str(temp), GITHUB_SHA="commit", GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="2", TUIST_ELIXIR_CACHE_BENCHMARK_COMPILATION=compilation, ERL_COMPILER_OPTIONS="[deterministic]" if compilation == "deterministic" else "", BENCH_JOB_STARTED=str(benchmark.time.time() - setup_elapsed)), patch.object(benchmark.subprocess, "Popen", FakeProcess), patch.object(benchmark.platform, "platform", return_value="test-linux"), patch.object(benchmark.os, "killpg") as killpg, patch("builtins.print"):
                if expected_error:
                    with self.assertRaises(expected_error):
                        benchmark.main()
                else:
                    benchmark.main()
            self.assertEqual(signal.getsignal(signal.SIGTERM), handler)
            self.assertEqual(modes, ["seed", "disabled", "remote", "remote", "disabled"][:expected_samples])
            self.assertEqual((server / "mix.exs").read_text(), self.source)
            self.assertFalse((temp / "elixir-cache-benchmark/pristine-deps").exists())
            samples = json.loads((temp / "elixir-cache-benchmark/samples.json").read_text())
            self.assertEqual(len(samples), expected_samples)
            metadata = json.loads((temp / "elixir-cache-benchmark/environment.json").read_text())
            self.assertEqual(metadata["compilation"], compilation)
            options = "[deterministic]" if compilation == "deterministic" else ""
            self.assertEqual(metadata["erl_compiler_options"], options)
            self.assertTrue(all(sample["compilation"] == compilation and sample["erl_compiler_options"] == options for sample in samples))
            if interruption is not None:
                self.assertEqual(killpg.call_args_list, [call(123, signal.SIGTERM), call(123, signal.SIGKILL)])
                self.assertTrue(samples[0]["interrupted"])
                self.assertFalse(samples[0]["completed"])
                self.assertTrue(samples[0]["record_errors"])
            else:
                self.assertTrue(all(sample["compiled_apps"] == ["package", "tuist"] for sample in samples))
            if degraded:
                self.assertEqual(samples[2]["seeded_key_misses"], ["key"] if degraded == "same-key" else [])
                self.assertEqual(samples[2]["seeded_app_misses"], ["package"])
                self.assertTrue(samples[2]["degraded"])
            return timeouts


if __name__ == "__main__":
    unittest.main()
