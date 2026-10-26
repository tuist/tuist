# Android emulator on Tuist macOS

A manual GitHub Actions smoke for building an Android app, launching it on an
API 35 ARM64 emulator, injecting three taps, and exporting a 20-second MP4.
The tiny native Java app has no external dependencies, credentials or backend.
It continuously animates a circle and displays the tap count.

## Run

Changes to this fixture or its workflow on `feat/android-emulator-gpu-ci-pipeline`
also trigger a SwiftShader smoke, so the initial pipeline can be validated before
it reaches the default branch.

Once the workflow is on the default branch:

```sh
gh workflow run android-emulator-macos.yml -f gpu=swiftshader
gh run list --workflow android-emulator-macos.yml
# Use the run ID from the list:
gh run watch <run-id>
gh run download <run-id> -n android-macos-swiftshader
open demo.mp4
```

The workflow uses `runs-on: tuist-macos`, not GitHub-hosted macOS. SwiftShader
is the default software GPU backend. Repeat with `-f gpu=host` to compare the
VM's GPU backend. Results apply to the renderer tested, not every graphics mode.

The artifact includes `demo.mp4`, `demo.ffprobe.json`, `demo.apk`,
`screenshot.png`, `environment.txt`, `emulator.log`, `screenrecord.log`,
`launch.txt`, `logcat.txt` and `graphics.txt`. Available diagnostics and the APK
are uploaded even when boot or recording fails. A passing run checks that the
activity is foregrounded, all three taps reach the app, and ffprobe decodes at
least 100 frames across at least 10 seconds. Review the video for visual defects;
these checks alone do not prove pixel correctness.

## GPU vs. CPU virtualization

Software GPU rendering avoids a dependency on Metal/passthrough GPU support.
It does **not** replace the CPU hypervisor. Apple's ARM64 Android emulator needs
Hypervisor.framework, including usable nested virtualization when running inside
a VM. The driver checks `emulator -accel-check`, records `kern.hv_support`, and
requires `-accel on`. If the profile cannot supply it, the smoke fails explicitly
with diagnostics. It never silently switches to bare metal or a different
profile. A local successful build does not establish that this profile can boot
an emulator.

## Local checks

```sh
ANDROID_HOME="$HOME/Library/Android/sdk" bash android/gradlew \
  -p .github/scripts/android-emulator-smoke --no-daemon assembleDebug
python3 -m unittest discover -s .github/scripts/android-emulator-smoke -p '*_test.py'
actionlint .github/workflows/android-emulator-macos.yml
```

A full local run additionally needs Apple silicon macOS, Java, Android SDK tools,
API 35 platforms/build-tools and the `google_apis;arm64-v8a` system image, plus
ffprobe. Set `ANDROID_AVD_HOME` to a disposable directory and `SMOKE_OUTPUT` to
a directory containing the built APK as `demo.apk`, then invoke `run.py` with the
SDK's emulator, platform-tools and cmdline-tools on `PATH`. Only run it when
emulator port 5554 is free.
