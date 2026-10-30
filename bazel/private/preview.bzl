"""A local, explicit publication boundary, never a cached network action."""

def _runfile(ctx, file):
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path

def preview_executable(ctx, payload, ecosystem):
    sources = ctx.attr._sources[DefaultInfo].files.to_list()
    publisher = [file for file in sources if file.basename == "publish.py"][0]
    config = ctx.actions.declare_file(ctx.label.name + ".preview.json")
    ctx.actions.write(config, json.encode({
        "ecosystem": ecosystem,
        "target": str(ctx.attr.app.label),
    }))
    launcher = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(launcher, """#!/usr/bin/env bash
# Standard Bazel Bash runfiles initialization v3, including manifest-only mode.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo >&2 "ERROR: cannot find $f"; exit 1; }
set -e
publisher="$(rlocation '%s')"
config="$(rlocation '%s')"
payload="$(rlocation '%s')"
if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  cd "$BUILD_WORKSPACE_DIRECTORY"
fi
exec python3 "$publisher" --config "$config" --payload "$payload" "$@"
""" % (_runfile(ctx, publisher), _runfile(ctx, config), _runfile(ctx, payload)), is_executable = True)
    return [DefaultInfo(
        executable = launcher,
        runfiles = ctx.runfiles(files = sources + [config, payload]).merge(ctx.attr._sources[DefaultInfo].default_runfiles),
    )]
