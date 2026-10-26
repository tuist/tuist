#!/usr/bin/env python3
"""Run the demo on a real emulator; keep evidence even when a stage fails."""

import json
import os
from pathlib import Path
import platform
import subprocess
import time

SERIAL = "emulator-5554"
PACKAGE = "dev.tuist.emulatorsmoke"


def run(*args, check=True, timeout=30, **kwargs):
    result = subprocess.run(
        args, check=False, timeout=timeout, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, **kwargs,
    )
    if check and result.returncode:
        print(result.stdout.decode(errors="replace"), flush=True)
        result.check_returncode()
    return result


def adb(*args, **kwargs):
    return run("adb", "-s", SERIAL, *args, **kwargs)


def wait_for_boot(emulator, timeout=300):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if emulator.poll() is not None:
            raise RuntimeError("Emulator exited before boot; see emulator.log")
        try:
            result = adb("shell", "getprop", "sys.boot_completed", check=False, timeout=10)
            if result.returncode == 0 and result.stdout.strip() == b"1":
                return
        except subprocess.TimeoutExpired:
            pass
        time.sleep(2)
    raise TimeoutError("Emulator did not boot within 300 seconds; see emulator.log")


def validate_video(path):
    probe = run(
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
        "-show_streams", "-show_format", "-of", "json", str(path),
    ).stdout
    path.with_suffix(".ffprobe.json").write_bytes(probe)
    metadata = json.loads(probe)
    streams = metadata.get("streams", [])
    if (not streams or float(metadata["format"]["duration"]) < 10
            or int(streams[0].get("nb_read_frames", "0")) < 100):
        raise RuntimeError("Recording must contain at least 10 seconds and 100 video frames")


def main():
    output = Path(os.environ["SMOKE_OUTPUT"])
    output.mkdir(parents=True, exist_ok=True)
    gpu = os.environ.get("GPU_MODE", "swiftshader")
    if gpu not in ("swiftshader", "host"):
        raise ValueError("GPU_MODE must be swiftshader or host")
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise RuntimeError("This smoke requires an Apple silicon macOS runner")

    with (output / "environment.txt").open("wb") as log:
        for command in (("sw_vers",), ("uname", "-a"), ("sysctl", "kern.hv_support"),
                        ("emulator", "-version"), ("sdkmanager", "--list_installed")):
            log.write(run(*command, check=False).stdout)
        log.write(f"\nGPU mode: {gpu}\n".encode())
        acceleration = run("emulator", "-accel-check", check=False)
        log.write(acceleration.stdout)
    if acceleration.returncode:
        raise RuntimeError(
            "Hypervisor.framework is unavailable inside this runner. Software GPU rendering "
            "does not replace CPU/nested virtualization; see environment.txt"
        )

    run("avdmanager", "create", "avd", "--force", "--name", "tuist-smoke",
        "--package", "system-images;android-35;google_apis;arm64-v8a",
        "--device", "pixel_6", input=b"no\n", timeout=60)
    run("adb", "start-server")
    recorder = None
    with (output / "emulator.log").open("wb") as log:
        emulator = subprocess.Popen([
            "emulator", "-avd", "tuist-smoke", "-port", "5554", "-accel", "on",
            "-gpu", gpu, "-no-window", "-no-audio", "-no-snapshot", "-no-boot-anim",
            "-no-metrics", "-camera-back", "none", "-camera-front", "none",
            "-memory", "2048", "-cores", "2",
        ], stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_for_boot(emulator)
            adb("shell", "wm", "size", "720x1280")
            adb("shell", "input", "keyevent", "82")
            adb("install", "-r", str(output / "demo.apk"), timeout=60)
            adb("logcat", "-c")
            with (output / "screenrecord.log").open("wb") as recording_log:
                recorder = subprocess.Popen([
                    "adb", "-s", SERIAL, "shell", "screenrecord", "--size", "720x1280",
                    "--bit-rate", "4000000", "--time-limit", "20", "/sdcard/demo.mp4",
                ], stdout=recording_log, stderr=subprocess.STDOUT)
                time.sleep(2)
                launch = adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")
                (output / "launch.txt").write_bytes(launch.stdout)
                resumed = adb("shell", "dumpsys", "activity", "activities").stdout
                if not any(PACKAGE.encode() in line and b"ResumedActivity" in line
                           for line in resumed.splitlines()):
                    raise RuntimeError("Demo activity is not in the foreground; see launch.txt")
                for _ in range(3):
                    time.sleep(2)
                    adb("shell", "input", "tap", "360", "640")
                logs = adb("logcat", "-d", "-s", "TuistSmoke:I", "*:S").stdout
                if b"SMOKE_TAPS=3" not in logs:
                    raise RuntimeError("App did not handle all three taps; see logcat.txt")
                if recorder.wait(timeout=30):
                    raise RuntimeError("Screen recording failed; see screenrecord.log")
            adb("pull", "/sdcard/demo.mp4", str(output / "demo.mp4"))
            validate_video(output / "demo.mp4")
        finally:
            # All device calls are bounded, including evidence collection after a crash.
            for name, args in (
                ("logcat.txt", ("logcat", "-d")),
                ("screenshot.png", ("exec-out", "screencap", "-p")),
                ("graphics.txt", ("shell", "dumpsys", "SurfaceFlinger")),
            ):
                try:
                    result = adb(*args, check=False, timeout=10)
                    if result.returncode == 0:
                        (output / name).write_bytes(result.stdout)
                except subprocess.TimeoutExpired:
                    pass
            if recorder is not None and recorder.poll() is None:
                recorder.terminate()
                try:
                    recorder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    recorder.kill()
                    recorder.wait(timeout=5)
            emulator.terminate()
            try:
                emulator.wait(timeout=10)
            except subprocess.TimeoutExpired:
                emulator.kill()
                emulator.wait(timeout=5)


if __name__ == "__main__":
    main()
