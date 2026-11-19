# The web edge's build (web/, served at luft.work), in two targets so the Vite
# dev server can reuse the first:
#
# - luft_wasm_bindgen binds the core's wasm32 cdylib for the browser with the
#   wasm-bindgen CLI, which must match the wasm-bindgen crate in Cargo.lock.
# - luft_vite installs the locked npm dependencies (cached on package.json and
#   package-lock.json) and bundles the TypeScript edge with Vite, pointing its
#   `luft-core` import at the bindings through LUFT_CORE_DIR.
#
# Struo's javascript_build only accepts React Native dependency sets, hence
# these kinds.

def _host_tool(ctx, name):
    path = host_which(name)
    if not path:
        fail(ctx["label"]["id"] + ": `" + name + "` was not found; run `mise install` in luft/")
    return path

def _luft_wasm_bindgen_impl(ctx):
    modules = [dep["dylib"] for dep in ctx["deps"] if dep.get("dylib")]
    if len(modules) != 1:
        fail(ctx["label"]["id"] + ": depend on exactly one wasm32 cdylib rust_library")
    bindgen = _host_tool(ctx, "wasm-bindgen")
    name = ctx["attr"]["out_name"]
    files = [declare_output(name + suffix) for suffix in [".js", ".d.ts", "_bg.wasm", "_bg.wasm.d.ts"]]
    out_dir = files[0].rsplit("/", 1)[0]
    run_action(
        argv = [
            bindgen, "--target", "web", "--out-dir", out_dir, "--out-name", name,
            "--remove-name-section", "--remove-producers-section", modules[0],
        ],
        inputs = [modules[0]],
        outputs = files,
        toolchain_identity = "luft.web.wasm-bindgen.v1\x00" + host_command([bindgen, "--version"]).strip() + "\x00" + host_file_sha256(bindgen),
        identifier = "luft_wasm_bindgen",
        display_name = "Bind " + name + " for the browser",
    )
    return {"label_id": ctx["label"]["id"], "luft_wasm_package": out_dir, "luft_wasm_files": files}

luft_wasm_bindgen = target_kind(
    docs = "The core's wasm module with wasm-bindgen's JavaScript bindings, for the web edge.",
    attrs = [attr("out_name", "string", required = True, configurable = False)],
    deps = [dep("deps", ["rust_crate"], "The wasm32 cdylib to bind.")],
    providers = ["luft_wasm_package"],
    capabilities = [capability("build", ["default"])],
    impl = _luft_wasm_bindgen_impl,
)

def _luft_vite_impl(ctx):
    packages = [dep for dep in ctx["deps"] if dep.get("luft_wasm_package")]
    if len(packages) != 1:
        fail(ctx["label"]["id"] + ": depend on exactly one luft_wasm_bindgen target")
    core = packages[0]
    node = _host_tool(ctx, "node")
    npm = _host_tool(ctx, "npm")
    node_identity = "\x00node\x00" + host_command([node, "--version"]).strip() + "\x00npm\x00" + host_command([npm, "--version"]).strip()
    package_dir = ctx["attr"]["package_dir"]
    prefix = package_dir + "/"
    path_env = node.rsplit("/", 1)[0] + ":/usr/bin:/bin"

    # npm ci in its own action, so dependencies rebuild only when the lockfile changes.
    install = ctx["build_dir"] + "/install"
    manifests = []
    for name in ["package.json", "package-lock.json"]:
        manifest = install + "/" + name
        copy_path(prefix + name, manifest, inputs = [prefix + name], identifier = ctx["label"]["id"] + ":manifest:" + name)
        manifests.append(manifest)
    node_modules = install + "/node_modules"
    install_home = ctx["scratch_dir"] + "/install-home"
    run_action(
        argv = [npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund"],
        inputs = manifests,
        outputs = [node_modules],
        clean_paths = [node_modules],
        create_dirs = [install_home],
        cwd = install,
        env = {"CI": "1", "HOME": execution_path(install_home), "PATH": path_env},
        network = "unrestricted",
        toolchain_identity = "luft.web.npm-ci.v1" + node_identity,
        identifier = "luft_web_npm_ci",
        display_name = "Install the web edge's npm dependencies",
    )

    stage = ctx["build_dir"] + "/stage"
    sources = glob(ctx["srcs"])
    staged = []
    for source in sources:
        relative = source[len(prefix):] if source.startswith(prefix) else source
        copy_path(source, stage + "/" + relative, inputs = [source], identifier = ctx["label"]["id"] + ":stage:" + relative)
        staged.append(stage + "/" + relative)
    copy_path(node_modules, stage + "/node_modules", kind = "tree", inputs = [node_modules], identifier = ctx["label"]["id"] + ":stage:node_modules")

    dist = declare_output("dist")
    home = ctx["scratch_dir"] + "/home"
    run_action(
        argv = [node, "node_modules/vite/bin/vite.js", "build", "--outDir", execution_path(dist), "--emptyOutDir"],
        inputs = staged + [stage + "/node_modules"] + core["luft_wasm_files"],
        outputs = [dist],
        clean_paths = [dist],
        create_dirs = [home],
        cwd = stage,
        env = {
            "CI": "1",
            "HOME": execution_path(home),
            "PATH": path_env,
            "LUFT_CORE_DIR": execution_path(core["luft_wasm_package"]),
        },
        toolchain_identity = "luft.web.vite.v1" + node_identity,
        identifier = "luft_web_vite_build",
        display_name = "Bundle the web edge with Vite",
    )
    return {"label_id": ctx["label"]["id"], "luft_web_dist": dist}

luft_vite = target_kind(
    docs = "The web edge's static site, bundled by Vite with the core's wasm bindings.",
    attrs = [attr("package_dir", "string", required = True, configurable = False)],
    deps = [dep("deps", ["luft_wasm_package"], "The core's wasm bindings.")],
    providers = ["luft_web_dist"],
    capabilities = [capability("build", ["default"])],
    impl = _luft_vite_impl,
)
