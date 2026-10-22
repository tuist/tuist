defmodule TuistEx.Cache.CompilerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Cache.Compiler

  test "a missing rebar launcher is installed before its first fingerprint" do
    root =
      Path.join(
        System.tmp_dir!(),
        "tuist-rebar-install-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "src"))
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(root, "src/probe.app.src"),
      "{application, probe, [{vsn, \"1.0\"}, {modules, []}]}."
    )

    launcher = Path.join(root, "rebar3")
    stub(Mix.Rebar, :available?, fn :rebar3 -> File.regular?(launcher) end)
    stub(Mix.Rebar, :rebar_args, fn :rebar3, [] -> {launcher, []} end)

    expect(Mix.Tasks.Local.Rebar, :run, fn ["--force"] ->
      File.write!(launcher, "rebar launcher")
      File.chmod!(launcher, 0o755)
      :ok
    end)

    dependency = %Mix.Dep{
      app: :probe,
      manager: :rebar3,
      extra: [],
      opts: [dest: root],
      system_env: []
    }

    first = Compiler.config(dependency)
    assert [{^launcher, _}] = first[:rebar_toolchain]
    assert Compiler.config(dependency)[:rebar_toolchain] == first[:rebar_toolchain]
  end

  test "Hex generator provenance excludes only outputs absent from the package manifest" do
    root =
      Path.join(
        System.tmp_dir!(),
        "tuist-hex-generator-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "src"))
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(root, "src/probe.app.src"),
      "{application, probe, [{vsn, \"1.0\"}, {modules, []}]}."
    )

    File.write!(Path.join(root, "src/scanner.xrl"), "grammar input")
    metadata = Path.join(root, "hex_metadata.config")
    File.write!(metadata, ~s({<<"files">>, [<<"src/probe.app.src">>, <<"src/scanner.xrl">>]}.\n))
    stub(Mix.Rebar, :available?, fn :rebar3 -> true end)
    stub(Mix.Rebar, :rebar_args, fn :rebar3, [] -> {System.find_executable("elixir"), []} end)

    dependency = %Mix.Dep{
      app: :probe,
      scm: Hex.SCM,
      manager: :rebar3,
      extra: [],
      opts: [dest: root],
      system_env: []
    }

    config = Compiler.config(dependency)
    assert config[:generated_sources] == ["src/scanner.erl"]
    before = Compiler.source_tree(dependency, config)
    File.write!(Path.join(root, "src/scanner.erl"), "derived output")
    assert Compiler.source_tree(dependency, Compiler.config(dependency)) == before
    File.write!(metadata, ~s({<<"files">>, [<<"src/scanner.xrl">>, <<"src/scanner.erl">>]}.\n))
    assert Compiler.config(dependency)[:generated_sources] == []
    assert File.read!(Path.join(root, "src/scanner.erl")) == "derived output"
    File.write!(metadata, ~s({<<"files">>, [<<"src">>]}.\n))
    assert Compiler.config(dependency)[:generated_sources] == []
    assert File.read!(Path.join(root, "src/scanner.erl")) == "derived output"
  end

  test "invalid explicit builder settings fail with an actionable configuration error" do
    assert_raise Mix.Error, ~r/builders must be a keyword list/, fn ->
      Compiler.validate_builders!(builders: %{})
    end

    assert_raise Mix.Error, ~r/Invalid tuist cache builder for :probe/, fn ->
      Compiler.validate_builders!(builders: [probe: [platform: "image", output: ["priv/probe"]]])
    end
  end

  test "ordinary Erlang compilers and source paths are supported" do
    assert Compiler.supported_config?(erlc_options: [debug_info: true], erlc_paths: ["src"])
    assert Compiler.supported_config?(rebar: [erl_opts: [:debug_info], deps: []])
    assert Compiler.supported_config?(rebar: [profiles: [test: [plugins: [:covertool]]]])
    refute Compiler.unsupported_source?("src/parser.erl")
    refute Compiler.unsupported_source?("src/parser.yrl")
    refute Compiler.unsupported_source?("src/scanner.xrl")
  end

  test "rebar build plugins, hooks and external include paths remain unsupported" do
    for config <- [
          [plugins: [:pc]],
          [pre_hooks: [{:compile, ~c"make"}]],
          [provider_hooks: [post: [{:compile, :native}]]],
          [profiles: [prod: [plugins: [:pc]]]],
          [erl_opts: [{:i, ~c"../outside"}]],
          [src_dirs: [~c"/outside"]]
        ] do
      refute Compiler.supported_config?(rebar: config)
    end

    refute Compiler.supported_config?(erlc_include_path: "../outside")
    assert Compiler.unsupported_source?("rebar.config.script")
    refute Compiler.unsupported_source?("Makefile.win")
    refute Compiler.unsupported_source?("rebar.config.script", rebar: [])
    assert Compiler.unsupported_source?("priv/native.so")
    assert Compiler.unsupported_source?("src/probe.app.src.script", rebar: [])

    refute Compiler.unsupported_source?("src/probe.app.src.script",
             cache_builder: [platform: "audited"]
           )
  end

  test "inert project-plugin configuration and unrelated compile aliases do not reject bare builds" do
    assert Compiler.supported_config?(
             rebar: [
               grpc: [protos: [~c"proto"]],
               ct_compile_opts: [],
               covertool: [],
               escript_main_app: :probe
             ]
           )

    assert Compiler.supported_config?(aliases: ["compile.nimble": ["generate", "compile"]])
    refute Compiler.supported_config?(aliases: ["compile.elixir": ["generate", "compile.elixir"]])
    refute Compiler.supported_config?(aliases: [compile: ["generate", "compile"]])
  end

  test "effective project configuration preserves first-key semantics with stable key ordering" do
    assert Compiler.effective_config(version: "1", app: :probe, version: "ignored") ==
             [app: :probe, version: "1"]
  end

  test "builder set declarations normalize order, duplicates and omitted empty options" do
    dependency = %{app: :probe}
    first = [platform: "image", outputs: ["priv/b", "priv/a", "priv/a"], env: ["B", "A"]]
    second = [env: ["A", "B", "A"], inputs: [], outputs: ["priv/a", "priv/b"], platform: "image"]

    assert Compiler.builder(dependency, builders: [probe: first]) ==
             Compiler.builder(dependency, builders: [probe: second])
  end

  test "parser includes outside the modeled source tree bypass caching" do
    refute Compiler.supported_config?(yecc_options: [includefile: ~c"../parser.hrl"])
    refute Compiler.supported_config?(leex_options: [includefile: ~c"/tmp/scanner.hrl"])
    assert Compiler.supported_config?(yecc_options: [includefile: ~c"include/parser.hrl"])
  end

  test "custom builders require an explicit valid platform and safe generated paths" do
    dependency = %{app: :probe, manager: :mix, opts: [compile: "make"]}

    builder = [
      platform: "container-sha256:123",
      outputs: ["priv/native"],
      generated: ["priv/native"],
      env: ["CC"],
      inputs: ["toolchain.json"]
    ]

    assert Compiler.builder(dependency, builders: [probe: builder]) == builder ++ [tools: []]
    assert Compiler.supported_manager?(dependency, builder)
    refute Compiler.supported_manager?(%{dependency | opts: [compile: false]}, builder)
    refute Compiler.supported_manager?(dependency)
    assert Compiler.supported_config?(cache_builder: builder, compilers: [:elixir_make])
    refute Compiler.unsupported_source?("c_src/probe.c", cache_builder: builder)

    for invalid <- [
          [],
          [platform: ""],
          [platform: "image", generated: ["../outside"]],
          [platform: "image", generated: ["priv/../lib"]],
          [platform: "image", generated: ["."]],
          [platform: "image", generated: ["_build"]],
          [platform: "image", env: ["INVALID=VALUE"]],
          [platform: "image", unknown: true]
        ] do
      invalid = Keyword.put_new(invalid, :outputs, [])

      assert catch_throw(Compiler.builder(dependency, builders: [probe: invalid])) ==
               :unmodeled_input
    end
  end
end
