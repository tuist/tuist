"""Publish native executable targets and their declared runtime files."""

load("@rules_python//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//private:preview.bzl", "preview_executable")

def _path(file):
    if file.short_path.startswith("../"):
        return "external/" + file.short_path[3:]
    return file.short_path

def _executable_preview_impl(ctx):
    binary = ctx.executable.binary
    info = ctx.attr.binary[DefaultInfo]
    runtime = ctx.attr._runtime[PyRuntimeInfo]
    packager = [file for file in ctx.attr._sources[DefaultInfo].files.to_list() if file.basename == "executable.py"][0]
    files = {_path(binary): binary}
    runfiles_root = _path(binary) + ".runfiles/"
    for file in info.default_runfiles.files.to_list():
        files[_path(file)] = file
        key = file.short_path[3:] if file.short_path.startswith("../") else ctx.workspace_name + "/" + file.short_path
        files[runfiles_root + key] = file
    for link in info.default_runfiles.symlinks.to_list():
        files[runfiles_root + ctx.workspace_name + "/" + link.path] = link.target_file
    for link in info.default_runfiles.root_symlinks.to_list():
        files[runfiles_root + link.path] = link.target_file
    config = ctx.actions.declare_file(ctx.label.name + ".distribution.json")
    ctx.actions.write(config, json.encode({
        "executable": _path(binary),
        "files": {name: file.path for name, file in files.items()},
        "empty_files": [runfiles_root + name for name in info.default_runfiles.empty_filenames.to_list()],
    }))
    archive = ctx.actions.declare_file(ctx.label.name + ".zip")
    ctx.actions.run(
        executable = runtime.interpreter,
        arguments = [packager.path, config.path, archive.path],
        inputs = depset([packager, config] + files.values(), transitive = [runtime.files]),
        outputs = [archive],
        mnemonic = "TuistExecutablePackage",
    )
    return preview_executable(ctx, archive, "executable", ctx.attr.binary.label)

executable_preview = rule(
    implementation = _executable_preview_impl,
    executable = True,
    attrs = {
        "binary": attr.label(mandatory = True, executable = True, cfg = "target"),
        "_sources": attr.label(default = Label("//private:sources")),
        "_runtime": attr.label(default = Label("@python_3_12//:py3_runtime"), cfg = "exec"),
    },
    doc = "Package an executable and its runfiles; publish only when run with --publish.",
)
