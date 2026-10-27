# Android nested KVM acceptance fixture

The `nested_kvm` mode of `.github/workflows/linux-runners-staging-smoke.yml`
runs this project directly as the unprivileged runner user on
`tuist-staging-linux-kvm`. Keep it on a native job: a Docker job container
would need its own explicit device forwarding and test a different path.
The fixture installs emulator userspace libraries inside the job's container;
the base runner image includes the SDK but not the emulator's X11/audio libraries.
Keep SDK installation and test execution non-root; sudo is only for apt setup.

Pinned comparison toolchain: Gradle 8.11.1, AGP 8.7.3, Kotlin 2.0.21,
Macrobenchmark 1.3.3 and Java/Kotlin JVM target 17. Both modules use a Pixel 6 API 34 AOSP x86_64 Gradle
Managed Device, sequentially to keep memory bounded. The app's instrumented
test checks the guest API and ABI. The separate self-instrumenting test module
measures 15 cold starts of a profileable, non-debuggable benchmark build.
Only the `EMULATOR` benchmark error is suppressed; results qualify this pool's
execution path, not physical-device performance.

Preserve the KVM acceleration check, XML test results, benchmark JSON and
traces. A successful Gradle exit without executed tests is not acceptance.
