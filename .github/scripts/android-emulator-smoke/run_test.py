import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import run as smoke


class BootTests(unittest.TestCase):
    @patch.object(smoke.time, "sleep")
    @patch.object(smoke, "adb")
    def test_waits_through_offline_device_and_adb_timeout(self, adb, sleep):
        adb.side_effect = [
            Mock(returncode=1, stdout=b"device offline"),
            subprocess.TimeoutExpired("adb", 10),
            Mock(returncode=0, stdout=b"1\n"),
        ]
        smoke.wait_for_boot(Mock(poll=Mock(return_value=None)))
        self.assertEqual(adb.call_count, 3)
        self.assertEqual(sleep.call_count, 2)
        self.assertEqual(adb.call_args.kwargs["timeout"], 10)

    @patch.object(smoke, "adb")
    def test_fails_immediately_if_emulator_exits(self, adb):
        with self.assertRaisesRegex(RuntimeError, "exited before boot"):
            smoke.wait_for_boot(Mock(poll=Mock(return_value=1)))
        adb.assert_not_called()

    @patch.object(smoke.time, "monotonic", side_effect=[0, 301])
    @patch.object(smoke, "adb")
    def test_boot_deadline_is_bounded(self, adb, monotonic):
        with self.assertRaises(TimeoutError):
            smoke.wait_for_boot(Mock(poll=Mock(return_value=None)))
        adb.assert_not_called()


class VideoTests(unittest.TestCase):
    def validate(self, metadata):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "demo.mp4"
            with patch.object(smoke, "run", return_value=Mock(stdout=json.dumps(metadata).encode())):
                smoke.validate_video(path)
            self.assertEqual(json.loads(path.with_suffix(".ffprobe.json").read_bytes()), metadata)

    def test_accepts_decoded_recording(self):
        self.validate({"format": {"duration": "20"}, "streams": [{"nb_read_frames": "600"}]})

    def test_rejects_missing_video(self):
        with self.assertRaises(RuntimeError):
            self.validate({"format": {"duration": "20"}, "streams": []})

    def test_rejects_short_or_undecodable_recordings(self):
        for duration, frames in (("2", "120"), ("20", "0"), ("20", "99")):
            with self.subTest(duration=duration, frames=frames), self.assertRaises(RuntimeError):
                self.validate({"format": {"duration": duration}, "streams": [{"nb_read_frames": frames}]})


class HypervisorTests(unittest.TestCase):
    @patch.object(smoke.platform, "system", return_value="Darwin")
    @patch.object(smoke.platform, "machine", return_value="arm64")
    @patch.object(smoke, "run")
    @patch.object(smoke.subprocess, "Popen")
    def test_unavailable_hvf_keeps_diagnostics_and_never_launches(self, popen, run, machine, system):
        run.return_value = Mock(returncode=1, stdout=b"HVF unavailable\n")
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(smoke.os.environ, {"SMOKE_OUTPUT": directory, "GPU_MODE": "swiftshader"}):
                with self.assertRaisesRegex(RuntimeError, "Hypervisor.framework is unavailable"):
                    smoke.main()
            self.assertIn("HVF unavailable", (Path(directory) / "environment.txt").read_text())
        popen.assert_not_called()
        self.assertEqual(run.call_args.args, ("emulator", "-accel-check"))


class CleanupTests(unittest.TestCase):
    @patch.object(smoke.platform, "system", return_value="Darwin")
    @patch.object(smoke.platform, "machine", return_value="arm64")
    @patch.object(smoke, "run", return_value=Mock(returncode=0, stdout=b"diagnostics"))
    @patch.object(smoke, "wait_for_boot", side_effect=TimeoutError("boot timed out"))
    @patch.object(smoke.subprocess, "Popen")
    def test_boot_failure_collects_evidence_and_terminates_emulator(self, popen, boot, run, machine, system):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(smoke.os.environ, {"SMOKE_OUTPUT": directory, "GPU_MODE": "swiftshader"}):
                with self.assertRaisesRegex(TimeoutError, "boot timed out"):
                    smoke.main()
            self.assertEqual((Path(directory) / "logcat.txt").read_bytes(), b"diagnostics")
            self.assertTrue((Path(directory) / "emulator.log").exists())
        popen.return_value.terminate.assert_called_once()
        popen.return_value.wait.assert_called_once_with(timeout=10)
        arguments = popen.call_args.args[0]
        self.assertEqual(arguments[arguments.index("-gpu") + 1], "swiftshader")
        self.assertEqual(arguments[arguments.index("-accel") + 1], "on")


if __name__ == "__main__":
    unittest.main()
