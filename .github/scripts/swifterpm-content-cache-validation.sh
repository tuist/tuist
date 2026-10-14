#!/usr/bin/env bash
set -euo pipefail

baseline=ece71f50d8373c8a55782bcbc10d06b9f152c86f
accepted=eaa1841722280f975e5a81cc3c28158ba7ac968e
state="$HOME/.cache/swifterpm-content-validation"
products="$state/products"
mkdir -p .validation-evidence .validation-transfer "$state"

git show "$accepted:Tuist.swift" > Tuist.swift
git show "$accepted:.github/scripts/retain-swiftpm-manifest-cache.sh" > "$RUNNER_TEMP/retain-manifests.sh"

if [[ "$GITHUB_RUN_ATTEMPT" == 1 ]]; then
  test ! -e .build
  mkdir -p "$state/workspace"
  ln -s "$state/workspace" .build
  bash "$RUNNER_TEMP/retain-manifests.sh"
  tuist install --force-resolved-versions --cache-path "$HOME/.cache/swifterpm" --cached-directory-materialization=symlink

  if [[ "$VALIDATION_VARIANT" == baseline ]]; then
    git show "$baseline:swifterpm/Sources/swifterpm/Manifest.swift" > swifterpm/Sources/swifterpm/Manifest.swift
    git show "$baseline:swifterpm/Sources/swifterpm/PackageInfoCache.swift" > swifterpm/Sources/swifterpm/PackageInfoCache.swift
    /usr/bin/ruby <<'RUBY'
path = 'swifterpm/Sources/swifterpm/Manifest.swift'
source = File.read(path)
source.sub!('static func dumpPackage(packageDir: URL, disableSandbox: Bool)', 'static func dumpPackage(packageDir: URL, disableSandbox: Bool, cacheFile: URL? = nil)')
source.sub!('static func dumpPackageJSON(packageDir: URL, disableSandbox: Bool)', 'static func dumpPackageJSON(packageDir: URL, disableSandbox: Bool, cacheFile: URL? = nil)')
source.sub!('    static let cacheFile = "package.json"', <<~SWIFT)
    static let cacheFile = "package.json"
    static func localCacheFilePath(rootPackageDir: URL, packageDir: URL) -> URL {
        cacheFilePath(packageDir: packageDir)
    }
SWIFT
File.write(path, source)
RUBY
  fi

  tuist generate tuist ProjectDescription --configuration Release --no-open
  xcodebuild build -workspace Tuist.xcworkspace -scheme tuist \
    -configuration Release \
    -derivedDataPath "$RUNNER_TEMP/content-cache-build" \
    CONFIGURATION_BUILD_DIR="$products" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    > .validation-evidence/build.log 2>&1
else
  tar -xzf .validation-transfer/state.tgz -C "$HOME"
  test ! -e .build
  ln -s "$state/workspace" .build
  bash "$RUNNER_TEMP/retain-manifests.sh"
  /usr/bin/ruby .github/scripts/swifterpm-content-cache-validation.rb verify "$state/seed.json"
fi

xcodebuild -version > .validation-evidence/toolchain.txt
sw_vers >> .validation-evidence/toolchain.txt
sysctl -n machdep.cpu.brand_string >> .validation-evidence/toolchain.txt
shasum -a 256 "$products/tuist" > .validation-evidence/binary.sha256
/usr/bin/ruby .github/scripts/swifterpm-content-cache-validation.rb snapshot .validation-evidence/before.json

if ! /usr/bin/time -p "$products/tuist" install --force-resolved-versions \
  --cache-path "$HOME/.cache/swifterpm" --cached-directory-materialization=symlink --report-timings \
  > .validation-evidence/install.log 2>&1; then
  cat .validation-evidence/install.log
  exit 1
fi
cat .validation-evidence/install.log
/usr/bin/ruby .github/scripts/swifterpm-content-cache-validation.rb compare .validation-evidence/before.json
git diff --exit-code -- Package.swift Package.resolved

if [[ "$GITHUB_RUN_ATTEMPT" == 1 ]]; then
  /usr/bin/ruby .github/scripts/swifterpm-content-cache-validation.rb snapshot "$state/seed.json"
  tar -czf .validation-transfer/state.tgz -C "$HOME" \
    .cache/swifterpm-content-validation .cache/swifterpm
fi
