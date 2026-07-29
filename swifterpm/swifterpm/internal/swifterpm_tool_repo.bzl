"""Repository rule that exposes SwifterPM-backed package resolve helpers."""

DEFAULT_SWIFTERPM_VERSION = "0.9.0"
DEFAULT_RELEASE_URL_TEMPLATE = "https://github.com/tuist/swifterpm/releases/download/{version}/swifterpm-{version}-{target}.tar.gz"

TOOL_CONFIG_DEFAULTS = {
    "build_path": ".build",
    "cache_path": ".cache",
    "config_path": ".config",
    "dependency_caching": True,
    "manifest_cache": "shared",
    "manifest_caching": True,
    "replace_scm_with_registry": False,
    "security_path": ".security",
    "use_registry_identity_for_scm": False,
}

_TOOL_CONFIG_ATTRS = {
    "build_path": attr.string(
        default = TOOL_CONFIG_DEFAULTS["build_path"],
        doc = "Package-relative or absolute path passed to SwifterPM as --build-path.",
    ),
    "cache_path": attr.string(
        default = TOOL_CONFIG_DEFAULTS["cache_path"],
        doc = "Package-relative or absolute path passed to SwifterPM as --cache-path.",
    ),
    "config_path": attr.string(
        default = TOOL_CONFIG_DEFAULTS["config_path"],
        doc = "Package-relative or absolute path passed to SwifterPM as --config-path.",
    ),
    "dependency_caching": attr.bool(
        default = TOOL_CONFIG_DEFAULTS["dependency_caching"],
        doc = "Whether dependency caching should be enabled.",
    ),
    "manifest_cache": attr.string(
        default = TOOL_CONFIG_DEFAULTS["manifest_cache"],
        values = ["shared", "local", "none"],
        doc = "SwiftPM-compatible manifest cache mode.",
    ),
    "manifest_caching": attr.bool(
        default = TOOL_CONFIG_DEFAULTS["manifest_caching"],
        doc = "Whether manifest caching should be enabled.",
    ),
    "replace_scm_with_registry": attr.bool(
        default = TOOL_CONFIG_DEFAULTS["replace_scm_with_registry"],
        doc = "SwiftPM-compatible registry replacement flag.",
    ),
    "security_path": attr.string(
        default = TOOL_CONFIG_DEFAULTS["security_path"],
        doc = "Package-relative or absolute path passed to SwifterPM as --security-path.",
    ),
    "use_registry_identity_for_scm": attr.bool(
        default = TOOL_CONFIG_DEFAULTS["use_registry_identity_for_scm"],
        doc = "SwiftPM-compatible registry identity flag.",
    ),
}

def tool_config_attrs():
    return _TOOL_CONFIG_ATTRS

def tool_config_defaults():
    return TOOL_CONFIG_DEFAULTS

def _host_target(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    arch = repository_ctx.os.arch.lower()

    if "mac" in os_name or "darwin" in os_name:
        if arch in ["aarch64", "arm64"]:
            return ("aarch64-apple-darwin", "swifterpm")
        if arch in ["x86_64", "amd64"]:
            return ("x86_64-apple-darwin", "swifterpm")

    if "linux" in os_name:
        if arch in ["x86_64", "amd64"]:
            return ("x86_64-unknown-linux-gnu", "swifterpm")

    if "windows" in os_name:
        if arch in ["x86_64", "amd64"]:
            return ("x86_64-pc-windows-msvc", "swifterpm.exe")

    fail("Unsupported SwifterPM host platform: os={}, arch={}".format(repository_ctx.os.name, repository_ctx.os.arch))

def _shell_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _download_swifterpm(repository_ctx, target, binary_name):
    version = repository_ctx.attr.version
    url = repository_ctx.attr.url_template.format(
        version = version,
        target = target,
    )
    archive_sha256 = repository_ctx.attr.archive_sha256s.get(target, "")

    repository_ctx.download_and_extract(
        output = ".",
        sha256 = archive_sha256,
        url = url,
    )

    if not repository_ctx.path(binary_name).exists:
        fail("SwifterPM release archive did not contain {}".format(binary_name))

    binary_sha256 = repository_ctx.attr.binary_sha256s.get(target, "")
    if binary_sha256:
        result = repository_ctx.execute([
            "sh",
            "-c",
            "shasum -a 256 {} | awk '{{print $1}}'".format(_shell_quote(binary_name)),
        ])
        if result.return_code != 0:
            fail("Failed to checksum {}: {}".format(binary_name, result.stderr))
        actual = result.stdout.strip()
        if actual != binary_sha256:
            fail("Checksum mismatch for {}: expected {}, got {}".format(binary_name, binary_sha256, actual))

    repository_ctx.execute(["chmod", "+x", binary_name])

def _link_local_swifterpm(repository_ctx, binary_name):
    if not repository_ctx.attr.local_binary:
        return
    repository_ctx.symlink(repository_ctx.attr.local_binary, binary_name)
    repository_ctx.execute(["chmod", "+x", binary_name])

def _common_swifterpm_arg_lines(repository_ctx):
    attr = repository_ctx.attr
    lines = [
        "args+=(--package-path \"${package_path}\")",
        "args+=(--build-path \"$(package_relative_path {})\")".format(_shell_quote(attr.build_path)),
        "args+=(--cache-path \"$(package_relative_path {})\")".format(_shell_quote(attr.cache_path)),
        "args+=(--security-path \"$(package_relative_path {})\")".format(_shell_quote(attr.security_path)),
    ]

    if attr.registries:
        lines.append("args+=(--config-path \"${runfiles_repo_dir}/registries.json\")")
    else:
        lines.append("args+=(--config-path \"$(package_relative_path {})\")".format(_shell_quote(attr.config_path)))

    if attr.dependency_caching:
        lines.append("args+=(--enable-dependency-cache)")
    else:
        lines.append("args+=(--disable-dependency-cache)")

    if not attr.manifest_caching or attr.manifest_cache == "none":
        lines.append("args+=(--disable-package-info-cache)")

    if attr.replace_scm_with_registry:
        lines.append("args+=(--replace-scm-with-registry)")

    if attr.use_registry_identity_for_scm:
        lines.append("args+=(--use-registry-identity-for-scm)")

    return lines

def _runner_script(repository_ctx, command, binary_name):
    command_args = []
    if command == "resolve":
        command_args = ["resolve", "--print-only", "--write"]
    elif command == "update":
        command_args = ["update", "--print-only", "--write"]
    elif command == "restore":
        command_args = ["restore"]
    else:
        fail("unknown SwifterPM command: {}".format(command))

    env_exports = []
    for key, value in repository_ctx.attr.env.items():
        env_exports.append("export {}={}".format(key, _shell_quote(value)))

    command_arg_lines = [
        "args+=({})".format(_shell_quote(arg))
        for arg in command_args
    ]

    return """#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
wrapper_path="$0"
wrapper_dir="$(cd "$(dirname "${{wrapper_path}}")" && pwd)"
package_path={package_path}
package_relative_path() {{
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "${{package_path}}/$1" ;;
  esac
}}
repo_name="$(basename "${{wrapper_dir}}")"
if [[ -n "${{RUNFILES_DIR:-}}" && -d "${{RUNFILES_DIR}}/${{repo_name}}" ]]; then
  runfiles_repo_dir="${{RUNFILES_DIR}}/${{repo_name}}"
elif [[ -d "${{wrapper_path}}.runfiles/${{repo_name}}" ]]; then
  runfiles_repo_dir="${{wrapper_path}}.runfiles/${{repo_name}}"
else
  runfiles_repo_dir="${{script_dir}}"
fi
{env_exports}
args=()
{arg_lines}
{command_arg_lines}
exec "${{runfiles_repo_dir}}/{binary_name}" "${{args[@]}}" "$@"
""".format(
        arg_lines = "\n".join(_common_swifterpm_arg_lines(repository_ctx)),
        binary_name = binary_name,
        command_arg_lines = "\n".join(command_arg_lines),
        env_exports = "\n".join(env_exports),
        package_path = _shell_quote(repository_ctx.attr.package_path),
    )

def _swifterpm_tool_repo_impl(repository_ctx):
    target, binary_name = _host_target(repository_ctx)

    if repository_ctx.attr.local_binary:
        _link_local_swifterpm(repository_ctx, binary_name)
    else:
        _download_swifterpm(repository_ctx, target, binary_name)

    if repository_ctx.attr.netrc:
        repository_ctx.symlink(repository_ctx.attr.netrc, ".netrc")

    if repository_ctx.attr.registries:
        repository_ctx.symlink(repository_ctx.attr.registries, "registries.json")

    for command in ["resolve", "update", "restore"]:
        script = "{}.sh".format(command)
        repository_ctx.file(
            script,
            _runner_script(repository_ctx, command, binary_name),
            executable = True,
        )

    data_files = ([":.netrc"] if repository_ctx.attr.netrc else []) + ([":registries.json"] if repository_ctx.attr.registries else [])
    exported_files = [binary_name] + [item[1:] for item in data_files]

    repository_ctx.file(
        "BUILD.bazel",
        """package(default_visibility = ["//visibility:public"])

exports_files({exported_files})

sh_binary(
    name = "resolve",
    srcs = ["resolve.sh"],
    data = [":{binary_name}"] + {data},
)

sh_binary(
    name = "update",
    srcs = ["update.sh"],
    data = [":{binary_name}"] + {data},
)

sh_binary(
    name = "restore",
    srcs = ["restore.sh"],
    data = [":{binary_name}"] + {data},
)
""".format(
            binary_name = binary_name,
            data = repr(data_files),
            exported_files = repr(exported_files),
        ),
    )

swifterpm_tool_repo = repository_rule(
    implementation = _swifterpm_tool_repo_impl,
    attrs = {
        "archive_sha256s": attr.string_dict(
            doc = "Optional archive SHA-256 values keyed by release target triple.",
        ),
        "binary_sha256s": attr.string_dict(
            doc = "Optional extracted-binary SHA-256 values keyed by release target triple.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables exported before running SwifterPM.",
        ),
        "local_binary": attr.string(
            doc = "Optional absolute path to a local SwifterPM binary for development.",
        ),
        "netrc": attr.label(
            allow_single_file = True,
            doc = "Accepted for API compatibility. SwifterPM currently authenticates through GITHUB_TOKEN or GH_TOKEN.",
        ),
        "package_path": attr.string(
            mandatory = True,
            doc = "Absolute path to the Swift package directory.",
        ),
        "registries": attr.label(
            allow_single_file = [".json"],
            doc = "Swift package registry configuration JSON.",
        ),
        "url_template": attr.string(
            default = DEFAULT_RELEASE_URL_TEMPLATE,
            doc = "GitHub release asset URL template with {version} and {target} placeholders.",
        ),
        "version": attr.string(
            default = DEFAULT_SWIFTERPM_VERSION,
            doc = "SwifterPM release version to download.",
        ),
    } | _TOOL_CONFIG_ATTRS,
    doc = "Downloads a released SwifterPM binary and exposes resolve/update/restore helpers.",
)
