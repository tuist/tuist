"""A local, explicit publication boundary, never a cached network action."""

load("@rules_python//python:py_runtime_info.bzl", "PyRuntimeInfo")

_RUNFILES_INIT = """#!/usr/bin/env bash
# Standard Bazel Bash runfiles initialization v3, including manifest-only mode.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo >&2 "ERROR: cannot find $f"; exit 1; }
set -e
if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  cd "$BUILD_WORKSPACE_DIRECTORY"
fi
"""

def _runfile(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path

def _executable(ctx, body, files, transitive_files = depset()):
    launcher = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(launcher, _RUNFILES_INIT + body, is_executable = True)
    return [DefaultInfo(
        executable = launcher,
        runfiles = ctx.runfiles(
            files = files,
            transitive_files = transitive_files,
        ).merge(ctx.attr._sources[DefaultInfo].default_runfiles),
    )]

def preview_executable(ctx, payload, ecosystem, target):
    sources = ctx.attr._sources[DefaultInfo].files.to_list()
    publisher = [file for file in sources if file.basename == "publish.py"][0]
    runtime = ctx.attr._runtime[PyRuntimeInfo]
    config = ctx.actions.declare_file(ctx.label.name + ".preview.json")
    ctx.actions.write(config, json.encode({
        "ecosystem": ecosystem,
        "target": str(target),
    }))
    return _executable(ctx, """python="$(rlocation '%s')"
publisher="$(rlocation '%s')"
config="$(rlocation '%s')"
payload="$(rlocation '%s')"
exec "$python" "$publisher" --config "$config" --payload "$payload" "$@"
""" % (_runfile(ctx, runtime.interpreter), _runfile(ctx, publisher), _runfile(ctx, config), _runfile(ctx, payload)), sources + [runtime.interpreter, config, payload], runtime.files)

def _login_impl(ctx):
    sources = ctx.attr._sources[DefaultInfo].files.to_list()
    auth = [file for file in sources if file.basename == "auth.py"][0]
    runtime = ctx.attr._runtime[PyRuntimeInfo]
    return _executable(ctx, """python="$(rlocation '%s')"
auth="$(rlocation '%s')"
exec "$python" "$auth" "$@"
""" % (_runfile(ctx, runtime.interpreter), _runfile(ctx, auth)), sources + [runtime.interpreter], runtime.files)

tuist_login = rule(
    implementation = _login_impl,
    executable = True,
    attrs = {
        "_sources": attr.label(default = Label("//private:sources")),
        "_runtime": attr.label(default = Label("@python_3_12//:py3_runtime"), cfg = "exec"),
    },
)
