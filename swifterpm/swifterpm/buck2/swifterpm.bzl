"""Buck2 helpers for restoring Swift package dependencies with SwifterPM."""

def _shell_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def swifterpm_restore(
        name,
        package = "Package.swift",
        resolved = None,
        swifterpm = "swifterpm",
        build_path = ".build",
        cache_path = ".cache/swifterpm",
        config_path = ".config",
        security_path = ".security",
        force_resolved_versions = False,
        skip_update = False,
        visibility = None):
    """Creates an executable Buck2 target that resolves and restores SwiftPM dependencies.

    The generated target is intended for Apple build setup steps that need
    `.build/checkouts` to exist before Buck2 compiles Swift targets that reference
    restored package sources.
    """

    srcs = [package]
    if resolved != None:
        srcs.append(resolved)

    extra_resolve_args = []
    if force_resolved_versions:
        extra_resolve_args.append("--force-resolved-versions")
    if skip_update:
        extra_resolve_args.append("--skip-update")

    cmd = """cat > "$OUT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

package_root="${SWIFTERPM_PACKAGE_ROOT:-${PWD}}"
if [[ ! -f "${package_root}/%s" ]]; then
  echo "error: ${package_root}/%s does not exist" >&2
  echo "Set SWIFTERPM_PACKAGE_ROOT to the directory containing %s." >&2
  exit 1
fi

swifterpm_bin="${SWIFTERPM_BIN:-%s}"
build_root=%s
cache_root=%s
config_root=%s
security_root=%s
case "${build_root}" in /*) ;; *) build_root="${package_root}/${build_root}" ;; esac
case "${cache_root}" in /*) ;; *) cache_root="${package_root}/${cache_root}" ;; esac
case "${config_root}" in /*) ;; *) config_root="${package_root}/${config_root}" ;; esac
case "${security_root}" in /*) ;; *) security_root="${package_root}/${security_root}" ;; esac
mkdir -p "${cache_root}"

common_args=(
  --package-path "${package_root}"
  --build-path "${build_root}"
  --cache-path "${cache_root}"
  --config-path "${config_root}"
  --security-path "${security_root}"
)

"${swifterpm_bin}" "${common_args[@]}" %s resolve --print-only --write
"${swifterpm_bin}" "${common_args[@]}" restore
EOF
chmod +x "$OUT"
""" % (
        package,
        package,
        package,
        swifterpm,
        _shell_quote(build_path),
        _shell_quote(cache_path),
        _shell_quote(config_path),
        _shell_quote(security_path),
        " ".join([_shell_quote(arg) for arg in extra_resolve_args]),
    )

    native.genrule(
        name = name,
        srcs = srcs,
        out = name + ".sh",
        cmd = cmd,
        executable = True,
        visibility = visibility,
    )
