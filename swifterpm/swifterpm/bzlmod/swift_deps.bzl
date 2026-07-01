"""Implementation for the SwifterPM-compatible `swift_deps` module extension."""

load("//swifterpm/internal:swifterpm_tool_repo.bzl", "DEFAULT_RELEASE_URL_TEMPLATE", "DEFAULT_SWIFTERPM_VERSION", "swifterpm_tool_repo", "tool_config_attrs", "tool_config_defaults")

def _swifterpm_config(modules):
    config = None
    for mod in modules:
        for tag in mod.tags.configure_swifterpm:
            if config != None:
                fail("Expected only one `configure_swifterpm` tag, but found multiple.")
            config = tag
    return config

def _swift_package_config(modules):
    config = None
    for mod in modules:
        for tag in mod.tags.configure_swift_package:
            if config != None:
                fail("Expected only one `configure_swift_package` tag, but found multiple.")
            config = tag
    return config

def _tool_config_kwargs(config):
    kwargs = {}
    for key in tool_config_attrs().keys():
        kwargs[key] = getattr(config, key) if config else tool_config_defaults()[key]
    return kwargs

def _declare_swift_package_repo(module_ctx, from_package, swift_package_config, swifterpm_config):
    if not from_package.declare_swift_package:
        return []

    package_swift = module_ctx.path(from_package.swift)
    package_path = str(package_swift.dirname)

    env = {}
    for key, value in from_package.env.items():
        env[key] = value
    for key in from_package.env_inherit:
        inherited = module_ctx.getenv(key)
        if inherited != None:
            env[key] = inherited

    version = DEFAULT_SWIFTERPM_VERSION
    url_template = DEFAULT_RELEASE_URL_TEMPLATE
    archive_sha256s = {}
    binary_sha256s = {}
    local_binary = ""
    if swifterpm_config:
        if swifterpm_config.version:
            version = swifterpm_config.version
        if swifterpm_config.url_template:
            url_template = swifterpm_config.url_template
        archive_sha256s = swifterpm_config.archive_sha256s
        binary_sha256s = swifterpm_config.binary_sha256s
        local_binary = swifterpm_config.local_binary

    swifterpm_tool_repo(
        name = "swift_package",
        archive_sha256s = archive_sha256s,
        binary_sha256s = binary_sha256s,
        env = env,
        local_binary = local_binary,
        netrc = from_package.netrc,
        package_path = package_path,
        registries = from_package.registries,
        url_template = url_template,
        version = version,
        **_tool_config_kwargs(swift_package_config)
    )
    return ["swift_package"]

def _declare_swift_deps_info_repo():
    _empty_repo(
        name = "swift_deps_info",
        message = "SwifterPM currently exposes the resolver helper only; package target metadata is not generated yet.",
    )
    return ["swift_deps_info"]

def _empty_repo_impl(repository_ctx):
    repository_ctx.file(
        "BUILD.bazel",
        """package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all",
    srcs = [],
)
""",
    )
    repository_ctx.file("README.md", repository_ctx.attr.message)

_empty_repo = repository_rule(
    implementation = _empty_repo_impl,
    attrs = {
        "message": attr.string(),
    },
)

def _swift_deps_impl(module_ctx):
    swift_package_config = _swift_package_config(module_ctx.modules)
    swifterpm_config = _swifterpm_config(module_ctx.modules)

    direct_deps = []
    for mod in module_ctx.modules:
        for from_package in mod.tags.from_package:
            direct_deps.extend(
                _declare_swift_package_repo(
                    module_ctx,
                    from_package,
                    swift_package_config,
                    swifterpm_config,
                ),
            )
            if from_package.declare_swift_deps_info:
                direct_deps.extend(_declare_swift_deps_info_repo())

    return module_ctx.extension_metadata(
        root_module_direct_deps = direct_deps,
        root_module_direct_dev_deps = [],
    )

_registry_attrs = {
    "netrc": attr.label(
        allow_single_file = True,
        doc = "A `.netrc` file. Accepted for API compatibility; SwifterPM currently uses GITHUB_TOKEN or GH_TOKEN.",
    ),
    "registries": attr.label(
        allow_single_file = [".json"],
        doc = "A Swift package registry configuration JSON file.",
    ),
}

_from_package_tag = tag_class(
    attrs = _registry_attrs | {
        "cached_json_directory": attr.string(
            doc = "Accepted for API compatibility with rules_swift_package_manager.",
        ),
        "declare_swift_deps_info": attr.bool(
            doc = "Declare a placeholder `swift_deps_info` repository.",
        ),
        "declare_swift_package": attr.bool(
            default = True,
            doc = "Declare the `swift_package` helper repository with `resolve`, `update`, and `restore` targets.",
        ),
        "env": attr.string_dict(
            doc = "Environment variables passed to SwifterPM.",
        ),
        "env_inherit": attr.string_list(
            doc = "Environment variables inherited by the module extension and passed to SwifterPM.",
        ),
        "resolve_transitive_local_dependencies": attr.bool(
            default = True,
            doc = "Accepted for API compatibility; SwifterPM handles local dependencies through the package manifest.",
        ),
        "resolved": attr.label(
            allow_files = [".resolved"],
            doc = "A `Package.resolved` file. Accepted for API compatibility.",
        ),
        "swift": attr.label(
            mandatory = True,
            allow_files = [".swift"],
            doc = "A `Package.swift` file.",
        ),
    },
    doc = "Load Swift package resolver helpers from `Package.swift` and `Package.resolved` files.",
)

_configure_package_tag = tag_class(
    attrs = {
        "build_file": attr.label(
            allow_single_file = True,
            doc = "Accepted for API compatibility; package BUILD generation is not implemented yet.",
        ),
        "init_submodules": attr.bool(default = False),
        "name": attr.string(mandatory = True),
        "patch_args": attr.string_list(default = ["-p0"]),
        "patch_cmds": attr.string_list(),
        "patch_cmds_win": attr.string_list(),
        "patch_tool": attr.string(default = "patch"),
        "patches": attr.label_list(allow_files = True),
        "publicly_expose_all_targets": attr.bool(default = False),
        "recursive_init_submodules": attr.bool(default = True),
        "target_deps": attr.string_list_dict(),
    },
    doc = "Accepted for API compatibility with rules_swift_package_manager.",
)

_configure_swift_package_tag = tag_class(
    attrs = tool_config_attrs(),
    doc = "Configure the generated `@swift_package` helper targets.",
)

_configure_swifterpm_tag = tag_class(
    attrs = {
        "archive_sha256s": attr.string_dict(
            doc = "Optional archive SHA-256 values keyed by release target triple.",
        ),
        "binary_sha256s": attr.string_dict(
            doc = "Optional extracted-binary SHA-256 values keyed by release target triple.",
        ),
        "local_binary": attr.string(
            doc = "Optional absolute path to a local SwifterPM binary for development.",
        ),
        "url_template": attr.string(
            default = DEFAULT_RELEASE_URL_TEMPLATE,
            doc = "GitHub release asset URL template with {version} and {target} placeholders.",
        ),
        "version": attr.string(
            default = DEFAULT_SWIFTERPM_VERSION,
            doc = "SwifterPM release version to download.",
        ),
    },
    doc = "Configure the released SwifterPM binary used by the helper targets.",
)

swift_deps = module_extension(
    implementation = _swift_deps_impl,
    tag_classes = {
        "configure_package": _configure_package_tag,
        "configure_swift_package": _configure_swift_package_tag,
        "configure_swifterpm": _configure_swifterpm_tag,
        "from_package": _from_package_tag,
    },
)
