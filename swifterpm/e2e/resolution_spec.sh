# End-to-end resolver tests against real-world Package.swift fixtures and
# SwiftPM's dependency-resolution graph fixtures.
#
# Each scenario pins an upstream repository to a specific commit, downloads the
# manifest file via raw.githubusercontent.com, resolves it with swifterpm, and
# verifies that the resulting Package.resolved is accepted by SwiftPM with
# `--force-resolved-versions`. Every scenario runs inside its own temp tree
# scoped through a RETURN trap so nothing leaks into the host filesystem or
# the user's caches.

# Pinned upstream sources.
POCKET_CASTS_REPO="Automattic/pocket-casts-ios"
POCKET_CASTS_SHA="43552c30d4121ea6bd8d2ea5cb53ee46c76f267e"
POCKET_CASTS_MANIFEST_PATH="Modules/Package.swift"

FIREFOX_IOS_REPO="mozilla-mobile/firefox-ios"
FIREFOX_IOS_SHA="d97982a167c3e15393607e027eca7f92b53dcad8"
FIREFOX_IOS_MANIFEST_PATH="Package.swift"

SWIFTPM_FIXTURES="${PWD}/e2e/fixtures/swiftpm/DependencyResolution/External"
SWIFTERPM_FIXTURES="${PWD}/e2e/fixtures/swifterpm"

prepare_isolated_state() {
  local tmp="$1"

  mkdir -p \
    "${tmp}/home" \
    "${tmp}/tmp" \
    "${tmp}/xdg-cache" \
    "${tmp}/xdg-config" \
    "${tmp}/xdg-data"
}

scoped_env() {
  local tmp="$1"
  shift

  env \
    HOME="${tmp}/home" \
    USERPROFILE="${tmp}/home" \
    TMPDIR="${tmp}/tmp" \
    XDG_CACHE_HOME="${tmp}/xdg-cache" \
    XDG_CONFIG_HOME="${tmp}/xdg-config" \
    XDG_DATA_HOME="${tmp}/xdg-data" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    "$@"
}

isolated_workspace() {
  # Stand up a temp tree with the manifest copied in. Returns the package
  # directory on stdout. Caller is responsible for the RETURN trap that
  # cleans `${tmp}` up.
  local repo="$1"
  local sha="$2"
  local manifest_relative_path="$3"
  local tmp="$4"

  local package_dir="${tmp}/package"
  mkdir -p "${package_dir}"

  local manifest_url="https://raw.githubusercontent.com/${repo}/${sha}/${manifest_relative_path}"
  if ! curl --fail --silent --show-error --location --retry 3 \
      --output "${package_dir}/Package.swift" "${manifest_url}"; then
    echo "failed to download ${manifest_url}" >&2
    return 1
  fi

  echo "${package_dir}"
}

copy_swiftpm_fixture() {
  local name="$1"
  local tmp="$2"
  local fixture_dir="${tmp}/${name}"

  cp -R "${SWIFTPM_FIXTURES}/${name}" "${fixture_dir}"
  echo "${fixture_dir}"
}

copy_swifterpm_fixture() {
  local name="$1"
  local tmp="$2"
  local fixture_dir="${tmp}/${name}"

  cp -R "${SWIFTERPM_FIXTURES}/${name}" "${fixture_dir}"
  echo "${fixture_dir}"
}

init_git_package() {
  local tmp="$1"
  local package_dir="$2"

  scoped_env "${tmp}" git -C "${package_dir}" -c init.defaultBranch=main init >/dev/null
  scoped_env "${tmp}" git -C "${package_dir}" checkout -B main >/dev/null 2>&1
  scoped_env "${tmp}" git -C "${package_dir}" config user.email "swifterpm-e2e@example.com"
  scoped_env "${tmp}" git -C "${package_dir}" config user.name "swifterpm e2e"
  scoped_env "${tmp}" git -C "${package_dir}" add .
  scoped_env "${tmp}" git -C "${package_dir}" commit -m "Initial import" >/dev/null
}

tag_git_package() {
  local tmp="$1"
  local package_dir="$2"
  shift 2

  local tag
  for tag in "$@"; do
    scoped_env "${tmp}" git -C "${package_dir}" tag "${tag}"
  done
}

start_registry_server() {
  local tmp="$1"
  local registry_dir="$2"

  python3 "${SWIFTERPM_FIXTURES}/registry-server.py" "${registry_dir}" >"${tmp}/registry.port" 2>"${tmp}/registry.log" &
  REGISTRY_SERVER_PID="$!"
  export REGISTRY_SERVER_PID
  for _ in {1..100}; do
    if [[ -s "${tmp}/registry.port" ]]; then
      REGISTRY_SERVER_PORT="$(cat "${tmp}/registry.port")"
      export REGISTRY_SERVER_PORT
      return 0
    fi
    if ! kill -0 "${REGISTRY_SERVER_PID}" >/dev/null 2>&1; then
      cat "${tmp}/registry.log" >&2 || true
      return 1
    fi
    sleep 0.05
  done
  cat "${tmp}/registry.log" >&2 || true
  return 1
}

stop_registry_server() {
  if [[ -n "${REGISTRY_SERVER_PID:-}" ]]; then
    kill "${REGISTRY_SERVER_PID}" >/dev/null 2>&1 || true
    wait "${REGISTRY_SERVER_PID}" 2>/dev/null || true
    unset REGISTRY_SERVER_PID
    unset REGISTRY_SERVER_PORT
    export REGISTRY_SERVER_PID
    export REGISTRY_SERVER_PORT
  fi
}

write_registry_package_archive() {
  local tmp="$1"
  local registry_dir="$2"
  local package_root
  package_root="$(copy_swifterpm_fixture "RegistryFoo" "${tmp}")" || return 1

  mkdir -p "${registry_dir}"
  (
    cd "${package_root}"
    zip -qry "${registry_dir}/registryfoo.zip" .
  )
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${registry_dir}/registryfoo.zip" | awk '{print $1}' >"${registry_dir}/checksum.txt"
  else
    shasum -a 256 "${registry_dir}/registryfoo.zip" | awk '{print $1}' >"${registry_dir}/checksum.txt"
  fi
}

resolve_package() {
  local tmp="$1"
  local package_dir="$2"
  local cache_dir="$3"
  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${cache_dir}" \
    --disable-package-info-cache \
    --quiet \
    resolve
}

canonical_path() {
  local path="$1"
  mkdir -p "${path}"
  (cd "${path}" && pwd -P)
}

normalize_json_file() {
  local source="$1"
  local swiftpm_scratch="$2"
  local swifterpm_scratch="$3"
  local swiftpm_cache="$4"
  local swifterpm_cache="$5"

  jq --sort-keys \
    --arg swiftpm_scratch "${swiftpm_scratch}" \
    --arg swifterpm_scratch "${swifterpm_scratch}" \
    --arg swiftpm_cache "${swiftpm_cache}" \
    --arg swifterpm_cache "${swifterpm_cache}" \
    '
      def replace_path($from; $to): split($from) | join($to);
      walk(
        if type == "string" then
          replace_path($swiftpm_scratch; "$SCRATCH")
          | replace_path($swifterpm_scratch; "$SCRATCH")
          | replace_path($swiftpm_cache; "$CACHE")
          | replace_path($swifterpm_cache; "$CACHE")
        else
          .
        end
      )
    ' "${source}"
}

normalize_package_resolved_file() {
  local source="$1"

  jq --sort-keys '
    def compact_state:
      with_entries(select(.value != null));

    def location_identity($location):
      ($location | split("/")[-1] | sub("\\.git$"; "") | ascii_downcase);

    def pin_location:
      .location // .repositoryURL // "";

    def pin_identity:
      if has("identity") then
        .identity
      elif has("location") then
        location_identity(.location)
      elif has("repositoryURL") then
        location_identity(.repositoryURL)
      elif has("package") then
        (.package | ascii_downcase)
      else
        ""
      end;

    def pin_kind:
      .kind // (if (pin_location | startswith("/")) then "localSourceControl" else "remoteSourceControl" end);

    def normalize_pin:
      {
        identity: pin_identity,
        kind: pin_kind,
        location: pin_location,
        state: (.state | compact_state)
      };

    {
      pins: (
        (if has("object") then .object.pins else .pins end)
        | map(normalize_pin)
        | sort_by(.identity, .location)
      )
    }
  ' "${source}"
}

compare_json_file() {
  local label="$1"
  local tmp="$2"
  local expected="$3"
  local actual="$4"
  local swiftpm_scratch="$5"
  local swifterpm_scratch="$6"
  local swiftpm_cache="$7"
  local swifterpm_cache="$8"

  local normalized_dir="${tmp}/normalized-state"
  mkdir -p "${normalized_dir}"

  local expected_normalized="${normalized_dir}/${label}.swiftpm.json"
  local actual_normalized="${normalized_dir}/${label}.swifterpm.json"
  normalize_json_file "${expected}" "${swiftpm_scratch}" "${swifterpm_scratch}" "${swiftpm_cache}" "${swifterpm_cache}" >"${expected_normalized}"
  normalize_json_file "${actual}" "${swiftpm_scratch}" "${swifterpm_scratch}" "${swiftpm_cache}" "${swifterpm_cache}" >"${actual_normalized}"

  if ! diff -u "${expected_normalized}" "${actual_normalized}"; then
    return 1
  fi

  echo "${label}=match"
}

compare_package_resolved_file() {
  local label="$1"
  local tmp="$2"
  local expected="$3"
  local actual="$4"

  local normalized_dir="${tmp}/normalized-state"
  mkdir -p "${normalized_dir}"

  local expected_normalized="${normalized_dir}/${label}.swiftpm.json"
  local actual_normalized="${normalized_dir}/${label}.swifterpm.json"
  normalize_package_resolved_file "${expected}" >"${expected_normalized}"
  normalize_package_resolved_file "${actual}" >"${actual_normalized}"

  if ! diff -u "${expected_normalized}" "${actual_normalized}"; then
    return 1
  fi

  echo "${label}=match"
}

compare_optional_json_file() {
  local label="$1"
  local tmp="$2"
  local expected="$3"
  local actual="$4"
  local swiftpm_scratch="$5"
  local swifterpm_scratch="$6"
  local swiftpm_cache="$7"
  local swifterpm_cache="$8"

  if [[ -f "${expected}" && -f "${actual}" ]]; then
    compare_package_resolved_file "${label}" "${tmp}" "${expected}" "${actual}"
  elif [[ ! -f "${expected}" && ! -f "${actual}" ]]; then
    echo "${label}=both-absent"
  else
    echo "${label}=presence-mismatch"
    return 1
  fi
}

compare_swiftpm_state_files() {
  local tmp="$1"
  local package_dir="$2"

  local swiftpm_scratch="${tmp}/swiftpm-scratch"
  local swifterpm_scratch="${tmp}/swifterpm-scratch"
  local swiftpm_cache="${tmp}/swiftpm-cache"
  local swifterpm_cache="${tmp}/swifterpm-cache"
  local swiftpm_resolved="${tmp}/Package.swiftpm.resolved"
  local swifterpm_resolved="${tmp}/Package.swifterpm.resolved"

  rm -f "${package_dir}/Package.resolved"
  scoped_env "${tmp}" swift package \
    --package-path "${package_dir}" \
    --scratch-path "${swiftpm_scratch}" \
    --cache-path "${swiftpm_cache}" \
    --disable-scm-to-registry-transformation \
    resolve >/dev/null 2>"${tmp}/swiftpm-resolve.stderr" || {
      cat "${tmp}/swiftpm-resolve.stderr" >&2
      return 1
    }
  if [[ -f "${package_dir}/Package.resolved" ]]; then
    cp "${package_dir}/Package.resolved" "${swiftpm_resolved}"
  fi

  rm -f "${package_dir}/Package.resolved"
  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${swifterpm_scratch}" \
    --cache-path "${swifterpm_cache}" \
    --disable-package-info-cache \
    --quiet \
    resolve >/dev/null
  if [[ -f "${package_dir}/Package.resolved" ]]; then
    cp "${package_dir}/Package.resolved" "${swifterpm_resolved}"
  fi

  swiftpm_scratch="$(canonical_path "${swiftpm_scratch}")"
  swifterpm_scratch="$(canonical_path "${swifterpm_scratch}")"
  swiftpm_cache="$(canonical_path "${swiftpm_cache}")"
  swifterpm_cache="$(canonical_path "${swifterpm_cache}")"

  compare_optional_json_file \
    "package-resolved" \
    "${tmp}" \
    "${swiftpm_resolved}" \
    "${swifterpm_resolved}" \
    "${swiftpm_scratch}" \
    "${swifterpm_scratch}" \
    "${swiftpm_cache}" \
    "${swifterpm_cache}" || return 1

  compare_json_file \
    "workspace-state" \
    "${tmp}" \
    "${swiftpm_scratch}/workspace-state.json" \
    "${swifterpm_scratch}/workspace-state.json" \
    "${swiftpm_scratch}" \
    "${swifterpm_scratch}" \
    "${swiftpm_cache}" \
    "${swifterpm_cache}"
}

swiftpm_accepts_lockfile() {
  local tmp="$1"
  local package_dir="$2"
  local cache_dir="$3"

  if [[ ! -f "${package_dir}/Package.resolved" ]]; then
    scoped_env "${tmp}" swift package \
      --package-path "${package_dir}" \
      --scratch-path "${cache_dir}/scratch" \
      --cache-path "${cache_dir}" \
      --disable-scm-to-registry-transformation \
      resolve >/dev/null 2>&1
    return
  fi

  scoped_env "${tmp}" swift package \
    --package-path "${package_dir}" \
    --scratch-path "${cache_dir}/scratch" \
    --cache-path "${cache_dir}" \
    --disable-scm-to-registry-transformation \
    --force-resolved-versions \
    resolve >/dev/null 2>&1
}

pin_count() {
  local package_dir="$1"
  if [[ ! -f "${package_dir}/Package.resolved" ]]; then
    echo "0"
    return
  fi
  jq '.pins | length' "${package_dir}/Package.resolved"
}

pin_state_value() {
  local package_dir="$1"
  local identity="$2"
  local field="$3"
  jq -r --arg identity "${identity}" --arg field "${field}" \
    '.pins[] | select(.identity == $identity) | .state[$field] // ""' \
    "${package_dir}/Package.resolved"
}

resolved_identities() {
  local package_dir="$1"
  jq -r '.pins[].identity' "${package_dir}/Package.resolved" | sort | tr '\n' ' ' | sed 's/ $//'
}

not_darwin() {
  [[ "$(uname -s)" != "Darwin" ]]
}

bazel_in_workspace() {
  local tmp="$1"
  local workspace="$2"
  shift 2

  (
    cd "${workspace}" &&
      scoped_env "${tmp}" bazel \
        --output_user_root="${tmp}/bazel-output" \
        --max_idle_secs=5 \
        --noworkspace_rc \
        --nohome_rc \
        --nosystem_rc \
        "$@"
  )
}

buck2_unavailable() {
  ! command -v buck2 >/dev/null 2>&1
}

buck2_in_workspace() {
  local tmp="$1"
  local workspace="$2"
  shift 2

  (
    cd "${workspace}" &&
      scoped_env "${tmp}" buck2 \
        --isolation-dir swifterpm-e2e \
        "$@"
  )
}

write_bazel_apple_rules_fixture() {
  local workspace="$1"
  local dependency="$2"
  local swifterpm_bin="$3"
  local repo_root="$4"

  mkdir -p \
    "${dependency}/Sources/E2EDependency" \
    "${workspace}/Sources/Runner"

  cat >"${dependency}/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dependency",
    products: [
        .library(name: "E2EDependency", targets: ["E2EDependency"]),
    ],
    targets: [
        .target(name: "E2EDependency"),
    ]
)
EOF

  cat >"${dependency}/Sources/E2EDependency/E2EDependency.swift" <<'EOF'
public enum E2EDependency {
    public static func message() -> String {
        "linked-from-restored-checkout"
    }
}
EOF

  cat >"${workspace}/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AppleRulesIntegrationApp",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "../Dependency", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "Runner",
            dependencies: [
                .product(name: "E2EDependency", package: "Dependency"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
EOF

  cat >"${workspace}/MODULE.bazel" <<EOF
module(
    name = "swifterpm_apple_rules_e2e",
    version = "0.0.0",
)

bazel_dep(name = "apple_support", version = "2.5.4")
bazel_dep(name = "rules_apple", version = "4.3.3")
bazel_dep(
    name = "rules_swift",
    version = "3.6.1",
    repo_name = "build_bazel_rules_swift",
)
bazel_dep(name = "swifterpm", version = "0.9.0")

local_path_override(
    module_name = "swifterpm",
    path = "${repo_root}",
)

apple_cc_configure = use_extension(
    "@apple_support//crosstool:setup.bzl",
    "apple_cc_configure_extension",
)
use_repo(apple_cc_configure, "local_config_apple_cc")

swift_deps = use_extension("@swifterpm//:extensions.bzl", "swift_deps")
swift_deps.configure_swifterpm(
    local_binary = "${swifterpm_bin}",
)
swift_deps.from_package(
    swift = "//:Package.swift",
)
use_repo(swift_deps, "swift_package")
EOF

  cat >"${workspace}/BUILD.bazel" <<'EOF'
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@rules_apple//apple:macos.bzl", "macos_command_line_application")
load("@rules_apple//apple:versioning.bzl", "apple_bundle_version")

swift_library(
    name = "E2EDependency",
    srcs = [".build/checkouts/Dependency/Sources/E2EDependency/E2EDependency.swift"],
    module_name = "E2EDependency",
)

swift_library(
    name = "Logging",
    srcs = glob([".build/checkouts/swift-log/Sources/Logging/**/*.swift"]),
    module_name = "Logging",
    package_name = "swift_log",
)

swift_library(
    name = "RunnerSources",
    srcs = ["Sources/Runner/main.swift"],
    deps = [
        ":E2EDependency",
        ":Logging",
    ],
)

apple_bundle_version(
    name = "RunnerVersion",
    build_version = "1",
    short_version_string = "1.0",
)

macos_command_line_application(
    name = "Runner",
    bundle_id = "dev.tuist.swifterpm.e2e.runner",
    infoplists = [":Info.plist"],
    minimum_os_version = "15.0",
    version = ":RunnerVersion",
    deps = [":RunnerSources"],
)
EOF

  cat >"${workspace}/Sources/Runner/main.swift" <<'EOF'
import E2EDependency
import Logging

let remoteMessage: Logger.Message = "remote-dependency-linked"
print("\(E2EDependency.message()):\(remoteMessage.description):\(Logger.Level.info.rawValue)")
EOF

  cat >"${workspace}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Runner</string>
  <key>CFBundleIdentifier</key>
  <string>dev.tuist.swifterpm.e2e.runner</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Runner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
EOF
}

write_buck2_apple_build_fixture() {
  local workspace="$1"
  local dependency="$2"
  local swifterpm_bin="$3"
  local repo_root="$4"

  mkdir -p \
    "${dependency}/Sources/E2EDependency" \
    "${workspace}/build_defs" \
    "${workspace}/toolchains" \
    "${workspace}/Sources/Runner"

  cp "${repo_root}/swifterpm/buck2/swifterpm.bzl" "${workspace}/build_defs/swifterpm.bzl"

  cat >"${dependency}/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dependency",
    products: [
        .library(name: "E2EDependency", targets: ["E2EDependency"]),
    ],
    targets: [
        .target(name: "E2EDependency"),
    ]
)
EOF

  cat >"${dependency}/Sources/E2EDependency/E2EDependency.swift" <<'EOF'
public enum E2EDependency {
    public static func message() -> String {
        "linked-from-buck2-restored-checkout"
    }
}
EOF

  cat >"${workspace}/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Buck2AppleIntegrationApp",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "../Dependency", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "Runner",
            dependencies: [
                .product(name: "E2EDependency", package: "Dependency"),
            ]
        ),
    ]
)
EOF

  cat >"${workspace}/.buckconfig" <<'EOF'
[cells]
root = .
prelude = prelude
toolchains = toolchains
none = none

[cell_aliases]
config = prelude
fbcode = none
fbsource = none
buck = none

[external_cells]
prelude = bundled

[parser]
target_platform_detector_spec = target:root//...->prelude//platforms:default
EOF

  cat >"${workspace}/BUCK" <<EOF
load("//build_defs:swifterpm.bzl", "swifterpm_restore")

swifterpm_restore(
    name = "restore_swift_packages",
    package = "Package.swift",
    swifterpm = "${swifterpm_bin}",
    visibility = ["PUBLIC"],
)
EOF

  cat >"${workspace}/toolchains/BUCK" <<'EOF'
load("@prelude//toolchains:demo.bzl", "system_demo_toolchains")

system_demo_toolchains()
EOF

  cat >"${workspace}/Sources/Runner/main.swift" <<'EOF'
import E2EDependency

print(E2EDependency.message())
EOF
}

scenario_resolves_firefox_ios() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local package_dir
  package_dir="$(isolated_workspace \
    "${FIREFOX_IOS_REPO}" \
    "${FIREFOX_IOS_SHA}" \
    "${FIREFOX_IOS_MANIFEST_PATH}" \
    "${tmp}")" || return 1

  resolve_package "${tmp}" "${package_dir}" "${tmp}/cache" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "force-resolve=ok"
}

scenario_resolves_pocket_casts_ios() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local package_dir
  package_dir="$(isolated_workspace \
    "${POCKET_CASTS_REPO}" \
    "${POCKET_CASTS_SHA}" \
    "${POCKET_CASTS_MANIFEST_PATH}" \
    "${tmp}")" || return 1

  resolve_package "${tmp}" "${package_dir}" "${tmp}/cache" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "force-resolve=ok"
}

scenario_resolves_locked_swifterpm_fixture() {
  local fixture="$1"
  local expected_pins="$2"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local package_dir
  package_dir="$(copy_swifterpm_fixture "${fixture}" "${tmp}")" || return 1

  local expected_resolved="${tmp}/Package.expected.resolved"
  cp "${package_dir}/Package.resolved" "${expected_resolved}"

  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --skip-update \
    --quiet \
    resolve \
    --print-only >/dev/null || return 1
  compare_package_resolved_file \
    "package-resolved" \
    "${tmp}" \
    "${expected_resolved}" \
    "${package_dir}/Package.resolved" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  test "$(pin_count "${package_dir}")" = "${expected_pins}" || return 1
  echo "package-resolved=match"
  echo "skip-update-resolve=ok"
}

scenario_bazel_apple_rules_restores_dependency_and_links() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'bazel --output_user_root="${tmp}/bazel-output" shutdown >/dev/null 2>&1 || true; rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local workspace="${tmp}/workspace"
  local dependency="${tmp}/Dependency"
  local swifterpm_bin
  swifterpm_bin="$(cd "$(dirname "${SWIFTERPM_BIN}")" && pwd -P)/$(basename "${SWIFTERPM_BIN}")"
  local repo_root
  repo_root="$(pwd -P)"

  write_bazel_apple_rules_fixture \
    "${workspace}" \
    "${dependency}" \
    "${swifterpm_bin}" \
    "${repo_root}" || return 1
  init_git_package "${tmp}" "${dependency}" || return 1
  tag_git_package "${tmp}" "${dependency}" "1.0.0" || return 1

  bazel_in_workspace "${tmp}" "${workspace}" run @swift_package//:resolve \
    >"${tmp}/resolve.stdout" 2>"${tmp}/resolve.stderr" || {
      cat "${tmp}/resolve.stderr" >&2
      cat "${tmp}/resolve.stdout" >&2
      return 1
    }
  bazel_in_workspace "${tmp}" "${workspace}" run @swift_package//:restore \
    >"${tmp}/restore.stdout" 2>"${tmp}/restore.stderr" || {
      cat "${tmp}/restore.stderr" >&2
      cat "${tmp}/restore.stdout" >&2
      return 1
    }

  local checkout_source="${workspace}/.build/checkouts/Dependency/Sources/E2EDependency/E2EDependency.swift"
  if [[ ! -f "${checkout_source}" ]]; then
    find "${workspace}/.build" -maxdepth 4 -print >&2 || true
    return 1
  fi
  local remote_checkout_source="${workspace}/.build/checkouts/swift-log/Sources/Logging/Logger.swift"
  if [[ ! -f "${remote_checkout_source}" ]]; then
    find "${workspace}/.build" -maxdepth 5 -print >&2 || true
    return 1
  fi

  bazel_in_workspace "${tmp}" "${workspace}" run //:Runner \
    >"${tmp}/app.stdout" 2>"${tmp}/app.stderr" || {
      cat "${tmp}/app.stderr" >&2
      cat "${tmp}/app.stdout" >&2
      return 1
    }
  grep -q "linked-from-restored-checkout:remote-dependency-linked:info" "${tmp}/app.stdout" || {
    cat "${tmp}/app.stderr" >&2
    cat "${tmp}/app.stdout" >&2
    return 1
  }

  echo "checkout=present"
  echo "remote-checkout=present"
  echo "apple-rules-link=ok"
  echo "app-output=$(grep -m 1 "linked-from-restored-checkout:remote-dependency-linked:info" "${tmp}/app.stdout")"
}

scenario_buck2_apple_build_rule_restores_dependency_and_links() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'buck2 --isolation-dir swifterpm-e2e kill >/dev/null 2>&1 || true; rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local workspace="${tmp}/workspace"
  local dependency="${tmp}/Dependency"
  local swifterpm_bin
  swifterpm_bin="$(cd "$(dirname "${SWIFTERPM_BIN}")" && pwd -P)/$(basename "${SWIFTERPM_BIN}")"
  local repo_root
  repo_root="$(pwd -P)"

  write_buck2_apple_build_fixture \
    "${workspace}" \
    "${dependency}" \
    "${swifterpm_bin}" \
    "${repo_root}" || return 1
  init_git_package "${tmp}" "${dependency}" || return 1
  tag_git_package "${tmp}" "${dependency}" "1.0.0" || return 1

  buck2_in_workspace "${tmp}" "${workspace}" run :restore_swift_packages \
    >"${tmp}/restore.stdout" 2>"${tmp}/restore.stderr" || {
      cat "${tmp}/restore.stderr" >&2
      cat "${tmp}/restore.stdout" >&2
      return 1
    }

  local checkout_source="${workspace}/.build/checkouts/Dependency/Sources/E2EDependency/E2EDependency.swift"
  if [[ ! -f "${checkout_source}" ]]; then
    find "${workspace}/.build" -maxdepth 4 -print >&2 || true
    return 1
  fi
  local remote_checkout_source="${workspace}/.build/checkouts/swift-log/Sources/Logging/Logger.swift"
  if [[ ! -f "${remote_checkout_source}" ]]; then
    find "${workspace}/.build" -maxdepth 5 -print >&2 || true
    return 1
  fi

  swiftc \
    -emit-library \
    -emit-module \
    -module-name E2EDependency \
    "${checkout_source}" \
    -o "${tmp}/libE2EDependency.dylib" || return 1
  swiftc \
    -I "${tmp}" \
    -L "${tmp}" \
    -lE2EDependency \
    "${workspace}/Sources/Runner/main.swift" \
    -o "${tmp}/Runner" || return 1
  DYLD_LIBRARY_PATH="${tmp}" "${tmp}/Runner" >"${tmp}/app.stdout" 2>"${tmp}/app.stderr" || {
    cat "${tmp}/app.stderr" >&2
    cat "${tmp}/app.stdout" >&2
    return 1
  }
  grep -q "linked-from-buck2-restored-checkout" "${tmp}/app.stdout" || {
    cat "${tmp}/app.stderr" >&2
    cat "${tmp}/app.stdout" >&2
    return 1
  }

  echo "checkout=present"
  echo "remote-checkout=present"
  echo "buck2-restore-rule=ok"
  echo "app-output=$(grep -m 1 "linked-from-buck2-restored-checkout" "${tmp}/app.stdout")"
}

scenario_resolves_swiftpm_external_simple() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "Simple" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/Foo" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/Foo" "1.0.0" "1.1.0" "1.2.0" "1.2.3" || return 1

  local package_dir="${fixture_dir}/Bar"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "foo-version=$(pin_state_value "${package_dir}" "foo" "version")"
  echo "force-resolve=ok"
}

scenario_restore_copies_checkouts_on_ci() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "Simple" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/Foo" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/Foo" "1.0.0" "1.1.0" "1.2.0" "1.2.3" || return 1

  local package_dir="${fixture_dir}/Bar"
  resolve_package "${tmp}" "${package_dir}" "${tmp}/cache" >/dev/null || return 1
  rm -rf "${package_dir}/.build"

  scoped_env "${tmp}" env CI=1 "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --disable-package-info-cache \
    --quiet \
    restore >/dev/null || return 1

  local checkout="${package_dir}/.build/checkouts/Foo"
  test -d "${checkout}" || return 1
  test ! -L "${checkout}" || return 1
  test -f "${checkout}/Package.swift" || return 1

  echo "checkout=directory"
  echo "checkout-symlink=absent"
}

scenario_restore_symlinks_checkouts_on_ci_when_configured() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "Simple" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/Foo" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/Foo" "1.0.0" "1.1.0" "1.2.0" "1.2.3" || return 1

  local package_dir="${fixture_dir}/Bar"
  resolve_package "${tmp}" "${package_dir}" "${tmp}/cache" >/dev/null || return 1
  rm -rf "${package_dir}/.build"

  scoped_env "${tmp}" env CI=1 "${SWIFTERPM_BIN}" \
    --cached-directory-materialization symlink \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --disable-package-info-cache \
    --quiet \
    restore >/dev/null || return 1

  local checkout="${package_dir}/.build/checkouts/Foo"
  test -d "${checkout}" || return 1
  test -L "${checkout}" || return 1
  test -f "${checkout}/Package.swift" || return 1

  echo "checkout=symlink"
  echo "checkout-symlink=present"
}

scenario_resolves_swiftpm_external_complex() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "Complex" "${tmp}")" || return 1

  local package
  for package in "FisherYates" "PlayingCard" "deck-of-playing-cards"; do
    init_git_package "${tmp}" "${fixture_dir}/${package}" || return 1
    tag_git_package "${tmp}" "${fixture_dir}/${package}" "1.0.0" || return 1
  done

  local package_dir="${fixture_dir}/app"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "identities=$(resolved_identities "${package_dir}")"
  echo "force-resolve=ok"
}

scenario_resolves_swiftpm_branch_dependency() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "Branch" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/Foo" || return 1

  local package_dir="${fixture_dir}/Bar"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  local revision
  revision="$(pin_state_value "${package_dir}" "foo" "revision")"
  test -n "${revision}" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "foo-branch=$(pin_state_value "${package_dir}" "foo" "branch")"
  echo "foo-revision=present"
  echo "force-resolve=ok"
}

scenario_resolves_swiftpm_local_case_insensitive_dependency() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swiftpm_fixture "PackageLookupCaseInsensitive" "${tmp}")" || return 1

  local package_dir="${fixture_dir}/pkg"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "force-resolve=ok"
}

scenario_replace_scm_with_registry_uses_registry() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'stop_registry_server; rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local registry_dir="${tmp}/registry"
  write_registry_package_archive "${tmp}" "${registry_dir}" || return 1
  start_registry_server "${tmp}" "${registry_dir}" || return 1
  local registry_url="http://127.0.0.1:${REGISTRY_SERVER_PORT}"

  local package_dir
  package_dir="$(copy_swifterpm_fixture "RegistryTransformApp" "${tmp}")" || return 1

  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --default-registry-url "${registry_url}" \
    --replace-scm-with-registry \
    --disable-package-info-cache \
    --quiet \
    resolve >/dev/null

  local identity
  identity="$(jq -r '.pins[0].identity' "${package_dir}/Package.resolved")"
  local kind
  kind="$(jq -r '.pins[0].kind' "${package_dir}/Package.resolved")"
  test "${identity}" = "example.registryfoo" || return 1
  test "${kind}" = "registry" || return 1
  test -e "${package_dir}/.build/registry/downloads/example/registryfoo/1.0.0/Package.swift" || return 1
  test ! -e "${package_dir}/.build/checkouts/RegistryFoo" || return 1

  local archive
  archive="$(find "${tmp}/cache/registry/archives" -type f -name '*.zip' -print | head -n 1)"
  test -n "${archive}" || return 1
  printf 'corrupt archive' >"${archive}"
  rm -rf "${tmp}/cache/sources/example.registryfoo" "${package_dir}/.build/registry"

  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --default-registry-url "${registry_url}" \
    --disable-package-info-cache \
    --quiet \
    restore >/dev/null

  test -e "${package_dir}/.build/registry/downloads/example/registryfoo/1.0.0/Package.swift" || return 1

  stop_registry_server
  echo "identity=${identity}"
  echo "kind=${kind}"
  echo "registry-download=present"
  echo "checkout=absent"
  echo "corrupt-archive-redownload=ok"
}

scenario_replace_scm_with_registry_falls_back_to_scm_when_registry_has_no_versions() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'stop_registry_server; rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local registry_dir="${tmp}/registry"
  mkdir -p "${registry_dir}"
  touch "${registry_dir}/no-releases"
  start_registry_server "${tmp}" "${registry_dir}" || return 1
  local registry_url="http://127.0.0.1:${REGISTRY_SERVER_PORT}"

  local fixture_dir
  fixture_dir="$(copy_swifterpm_fixture "RegistryFallbackToSCM" "${tmp}")" || return 1

  local dependency_dir="${fixture_dir}/LocalRegistryFoo"
  init_git_package "${tmp}" "${dependency_dir}" || return 1
  tag_git_package "${tmp}" "${dependency_dir}" "1.0.0" || return 1
  dependency_dir="$(canonical_path "${dependency_dir}")"

  local package_dir="${fixture_dir}/App"

  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --default-registry-url "${registry_url}" \
    --replace-scm-with-registry \
    --disable-package-info-cache \
    --quiet \
    resolve >/dev/null

  local identity
  identity="$(jq -r '.pins[0].identity' "${package_dir}/Package.resolved")"
  local kind
  kind="$(jq -r '.pins[0].kind' "${package_dir}/Package.resolved")"
  local location
  location="$(jq -r '.pins[0].location' "${package_dir}/Package.resolved")"
  local version
  version="$(jq -r '.pins[0].state.version' "${package_dir}/Package.resolved")"

  # Identity is SCM-derived (`localregistryfoo`) now that we defer to
  # SwiftPM. The previous swifterpm rewrote it to the registry identity
  # `example.registryfoo` even on SCM fallback; SwiftPM's natural
  # output keeps the SCM identity.
  test "${identity}" = "localregistryfoo" || return 1
  test "${kind}" = "localSourceControl" || return 1
  test "${location}" = "${dependency_dir}" || return 1
  test "${version}" = "1.0.0" || return 1
  test -e "${package_dir}/.build/checkouts/LocalRegistryFoo/Package.swift" || return 1
  test ! -e "${package_dir}/.build/registry/downloads/example/registryfoo/1.0.0/Package.swift" || return 1

  stop_registry_server
  echo "identity=${identity}"
  echo "kind=${kind}"
  echo "version=${version}"
  echo "checkout=present"
  echo "registry-download=absent"
}

scenario_replace_scm_with_registry_skips_directly_incompatible_candidate() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'stop_registry_server; rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local registry_dir="${tmp}/registry"
  mkdir -p "${registry_dir}"
  start_registry_server "${tmp}" "${registry_dir}" || return 1
  local registry_url="http://127.0.0.1:${REGISTRY_SERVER_PORT}"

  local fixture_dir
  fixture_dir="$(copy_swifterpm_fixture "GreedyLookahead" "${tmp}")" || return 1

  local proto_dir="${fixture_dir}/Proto"
  init_git_package "${tmp}" "${proto_dir}" || return 1
  tag_git_package "${tmp}" "${proto_dir}" "1.35.1" "1.38.0" || return 1
  scoped_env "${tmp}" git clone --bare "${proto_dir}" "${fixture_dir}/Proto.git" >/dev/null 2>&1 || return 1

  local service_dir="${fixture_dir}/Service"
  init_git_package "${tmp}" "${service_dir}" || return 1
  tag_git_package "${tmp}" "${service_dir}" "2.3.0" || return 1
  cp "${fixture_dir}/ServiceIncompatible/Package.swift" "${service_dir}/Package.swift"
  scoped_env "${tmp}" git -C "${service_dir}" add Package.swift
  scoped_env "${tmp}" git -C "${service_dir}" commit -m "Raise proto lower bound" >/dev/null
  tag_git_package "${tmp}" "${service_dir}" "2.4.0" || return 1
  scoped_env "${tmp}" git clone --bare "${service_dir}" "${fixture_dir}/Service.git" >/dev/null 2>&1 || return 1

  local package_dir="${fixture_dir}/App"
  scoped_env "${tmp}" swift package --package-path "${package_dir}" resolve >/dev/null 2>&1 || return 1
  local swiftpm_service_version
  swiftpm_service_version="$(pin_state_value "${package_dir}" "service" "version")"
  test "${swiftpm_service_version}" = "2.3.0" || return 1

  rm -rf "${package_dir}/.build" "${package_dir}/Package.resolved"

  scoped_env "${tmp}" "${SWIFTERPM_BIN}" \
    --package-path "${package_dir}" \
    --scratch-path "${package_dir}/.build" \
    --cache-path "${tmp}/cache" \
    --default-registry-url "${registry_url}" \
    --replace-scm-with-registry \
    --disable-package-info-cache \
    --quiet \
    resolve >/dev/null

  # Pins use SCM-derived identities now that the wrapper defers to
  # SwiftPM (the registry has no compatible versions, so SwiftPM keeps
  # the SCM identity). Look up by `service` and `proto`, not by the
  # registry identities the previous rewrite path produced.
  local swifterpm_service_version
  swifterpm_service_version="$(
    pin_state_value "${package_dir}" "service" "version"
  )"
  local proto_version
  proto_version="$(pin_state_value "${package_dir}" "proto" "version")"
  test "${swifterpm_service_version}" = "${swiftpm_service_version}" || return 1
  test "${proto_version}" = "1.35.1" || return 1

  stop_registry_server
  echo "swiftpm-service-version=${swiftpm_service_version}"
  echo "swifterpm-service-version=${swifterpm_service_version}"
  echo "proto-version=${proto_version}"
}

scenario_resolves_transitive_local_file_system_dependencies() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swifterpm_fixture "TransitiveLocal" "${tmp}")" || return 1
  local package_dir="${fixture_dir}/App"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1

  local identities
  identities="$(jq -r '.object.dependencies[].packageRef.identity' "${tmp}/swifterpm-scratch/workspace-state.json" | sort | tr '\n' ' ' | sed 's/ $//')"
  test "${identities}" = "localone localtwo" || return 1

  echo "workspace-state=match"
  echo "local-identities=${identities}"
}

scenario_resolves_pubgrub_shared_dependency_intersection() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swifterpm_fixture "PubGrubSharedDependency" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/A" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/A" "1.0.0" || return 1
  init_git_package "${tmp}" "${fixture_dir}/B" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/B" "1.0.0" || return 1
  init_git_package "${tmp}" "${fixture_dir}/Shared" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/Shared" \
    "2.0.0" "3.0.0" "3.6.9" "4.0.0" "5.0.0" || return 1

  local package_dir="${fixture_dir}/App"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  local shared_version
  shared_version="$(pin_state_value "${package_dir}" "shared" "version")"
  test "${shared_version}" = "3.6.9" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "shared-version=${shared_version}"
  echo "force-resolve=ok"
}

scenario_resolves_pubgrub_release_over_prerelease() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local fixture_dir
  fixture_dir="$(copy_swifterpm_fixture "PubGrubReleaseOverPrerelease" "${tmp}")" || return 1

  init_git_package "${tmp}" "${fixture_dir}/A" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/A" "1.0.0" || return 1
  init_git_package "${tmp}" "${fixture_dir}/B" || return 1
  tag_git_package "${tmp}" "${fixture_dir}/B" "1.0.0-prerelease-20240616" "1.0.0" || return 1

  local package_dir="${fixture_dir}/App"
  compare_swiftpm_state_files "${tmp}" "${package_dir}" || return 1
  swiftpm_accepts_lockfile "${tmp}" "${package_dir}" "${tmp}/swift-cache" || return 1

  local b_version
  b_version="$(pin_state_value "${package_dir}" "b" "version")"
  test "${b_version}" = "1.0.0" || return 1

  echo "pins=$(pin_count "${package_dir}")"
  echo "b-version=${b_version}"
  echo "force-resolve=ok"
}

scenario_manifest_cache_stays_under_build_directory() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  prepare_isolated_state "${tmp}"

  local package_dir
  package_dir="$(copy_swifterpm_fixture "Bare" "${tmp}")" || return 1

  resolve_package "${tmp}" "${package_dir}" "${tmp}/cache" || return 1

  test ! -e "${package_dir}/.swifterpm-manifest.json" || return 1
  test -e "${package_dir}/.build/swifterpm/manifests/package.json" || return 1

  echo "legacy-cache=absent"
  echo "manifest-cache=.build/swifterpm"
}

Describe "swifterpm resolve against real-world manifests"
  It "resolves Firefox iOS root Package.swift and emits a SwiftPM-acceptable lockfile"
    When call scenario_resolves_firefox_ios
    The status should be success
    The output should match pattern "pins=*"
    The output should include "force-resolve=ok"
  End

  It "resolves Pocket Casts iOS Modules/Package.swift and emits a SwiftPM-acceptable lockfile"
    When call scenario_resolves_pocket_casts_ios
    The status should be success
    The output should match pattern "pins=*"
    The output should include "force-resolve=ok"
  End

  It "resolves the large external dependencies fixture and preserves its lockfile"
    When call scenario_resolves_locked_swifterpm_fixture "ExternalDependenciesLarge" "69"
    The status should be success
    The output should include "pins=69"
    The output should include "package-resolved=match"
    The output should include "skip-update-resolve=ok"
  End

  It "resolves the larger external dependencies fixture and preserves its lockfile"
    When call scenario_resolves_locked_swifterpm_fixture "ExternalDependenciesLarger" "102"
    The status should be success
    The output should include "pins=102"
    The output should include "package-resolved=match"
    The output should include "skip-update-resolve=ok"
  End
End

Describe "swifterpm Bazel Apple rules integration"
  Skip if "requires macOS rules_apple toolchain" not_darwin

  It "restores a dependency into .build/checkouts and links it with rules_apple"
    When call scenario_bazel_apple_rules_restores_dependency_and_links
    The status should be success
    The output should include "checkout=present"
    The output should include "remote-checkout=present"
    The output should include "apple-rules-link=ok"
    The output should include "app-output=linked-from-restored-checkout:remote-dependency-linked:info"
  End
End

Describe "swifterpm Buck2 Apple build setup integration"
  Skip if "requires macOS Swift toolchain" not_darwin
  Skip if "requires buck2" buck2_unavailable

  It "restores a dependency into .build/checkouts and links it from an Apple build setup"
    When call scenario_buck2_apple_build_rule_restores_dependency_and_links
    The status should be success
    The output should include "checkout=present"
    The output should include "remote-checkout=present"
    The output should include "buck2-restore-rule=ok"
    The output should include "app-output=linked-from-buck2-restored-checkout"
  End
End

Describe "swifterpm resolve against SwiftPM dependency graph fixtures"
  It "matches SwiftPM's external simple version-selection scenario"
    When call scenario_resolves_swiftpm_external_simple
    The status should be success
    The output should include "pins=1"
    The output should include "foo-version=1.2.3"
    The output should include "package-resolved=match"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End

  It "copies restored source checkouts instead of symlinking them on CI"
    When call scenario_restore_copies_checkouts_on_ci
    The status should be success
    The output should include "checkout=directory"
    The output should include "checkout-symlink=absent"
  End

  It "can preserve symlinked source checkouts on CI when configured"
    When call scenario_restore_symlinks_checkouts_on_ci_when_configured
    The status should be success
    The output should include "checkout=symlink"
    The output should include "checkout-symlink=present"
  End

  It "matches SwiftPM's external complex transitive graph scenario"
    When call scenario_resolves_swiftpm_external_complex
    The status should be success
    The output should include "pins=3"
    The output should include "identities=deck-of-playing-cards fisheryates playingcard"
    The output should include "package-resolved=match"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End

  It "matches SwiftPM's branch dependency scenario"
    When call scenario_resolves_swiftpm_branch_dependency
    The status should be success
    The output should include "pins=1"
    The output should include "foo-branch=main"
    The output should include "foo-revision=present"
    The output should include "package-resolved=match"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End

  It "matches SwiftPM's local case-insensitive package lookup scenario"
    When call scenario_resolves_swiftpm_local_case_insensitive_dependency
    The status should be success
    The output should include "pins=0"
    The output should include "package-resolved=both-absent"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End

  It "matches SwiftPM's transitive local file-system dependency scenario"
    When call scenario_resolves_transitive_local_file_system_dependencies
    The status should be success
    The output should include "workspace-state=match"
    The output should include "local-identities=localone localtwo"
  End

  It "matches SwiftPM's shared dependency intersection scenario"
    When call scenario_resolves_pubgrub_shared_dependency_intersection
    The status should be success
    The output should include "pins=3"
    The output should include "shared-version=3.6.9"
    The output should include "package-resolved=match"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End

  It "matches SwiftPM's release-over-prerelease scenario"
    When call scenario_resolves_pubgrub_release_over_prerelease
    The status should be success
    The output should include "pins=2"
    The output should include "b-version=1.0.0"
    The output should include "package-resolved=match"
    The output should include "workspace-state=match"
    The output should include "force-resolve=ok"
  End
End

Describe "swifterpm registry integration"
  It "replaces source-control dependencies with registry downloads when requested"
    When call scenario_replace_scm_with_registry_uses_registry
    The status should be success
    The output should include "identity=example.registryfoo"
    The output should include "kind=registry"
    The output should include "registry-download=present"
    The output should include "checkout=absent"
    The output should include "corrupt-archive-redownload=ok"
  End

  It "falls back to source control when a registry identifier has no versions"
    When call scenario_replace_scm_with_registry_falls_back_to_scm_when_registry_has_no_versions
    The status should be success
    The output should include "identity=localregistryfoo"
    The output should include "kind=localSourceControl"
    The output should include "version=1.0.0"
    The output should include "checkout=present"
    The output should include "registry-download=absent"
  End

  It "matches SwiftPM when the newest candidate has an incompatible direct dependency"
    When call scenario_replace_scm_with_registry_skips_directly_incompatible_candidate
    The status should be success
    The output should include "swiftpm-service-version=2.3.0"
    The output should include "swifterpm-service-version=2.3.0"
    The output should include "proto-version=1.35.1"
  End

  It "stores manifest dump caches under .build/swifterpm"
    When call scenario_manifest_cache_stays_under_build_directory
    The status should be success
    The output should include "legacy-cache=absent"
    The output should include "manifest-cache=.build/swifterpm"
  End
End
