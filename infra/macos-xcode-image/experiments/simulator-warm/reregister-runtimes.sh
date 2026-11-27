#!/bin/bash
# Experiment: the runner image's runtime re-registration step, copied verbatim
# from infra/runner-image/runner.pkr.hcl. Run right after a reboot.
set -euo pipefail
PLIST=/Library/Developer/CoreSimulator/Images/images.plist
if ! sudo plutil -p $PLIST | grep personalizeAndMountAsCryptex >/dev/null; then echo 'no cryptex simulator runtimes to re-register'; exit 0; fi
if pgrep -x simdiskimaged >/dev/null; then echo 'simdiskimaged is already running; it would keep the cryptex registration' >&2; exit 1; fi
EXPECTED=$(sudo plutil -p $PLIST | grep -o 'com\.apple\.CoreSimulator\.SimRuntime\.[A-Za-z0-9.-]*' | sort -u | wc -l | tr -d ' ')
[ "$EXPECTED" -gt 0 ] || { echo 'images.plist names no simulator runtime' >&2; exit 1; }
sudo mv $PLIST /var/tmp/images.plist.cryptex
DMG=0; READY=0; for i in $(seq 1 150); do READY=$(xcrun simctl list runtimes -j 2>/dev/null | /opt/homebrew/bin/jq '[.runtimes[] | select(.isAvailable)] | length' 2>/dev/null || echo 0); DMG=$(sudo plutil -p $PLIST 2>/dev/null | grep -c mountAsDMG || true); [ "$DMG" -ge "$EXPECTED" ] && [ "$READY" -ge "$EXPECTED" ] && break; sleep 2; done
if [ "$DMG" -lt "$EXPECTED" ] || [ "$READY" -lt "$EXPECTED" ] || sudo plutil -p $PLIST | grep personalizeAndMountAsCryptex >/dev/null; then echo "WARNING: $DMG of $EXPECTED simulator runtimes re-registered as disk images, $READY available; keeping the cryptex registration" >&2; sudo plutil -p $PLIST 2>/dev/null | grep -E 'SimRuntime|mount' >&2 || true; sudo killall simdiskimaged 2>/dev/null || true; sudo mv /var/tmp/images.plist.cryptex $PLIST; touch /var/tmp/tuist-sim-runtimes-cryptex; exit 0; fi
sudo rm -f /var/tmp/images.plist.cryptex
xcrun simctl runtime list
