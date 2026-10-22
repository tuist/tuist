defmodule TuistEx.DependencyCacheTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 120_000

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "tuist-deps-cache-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    repo = Path.join(dir, "package")
    File.mkdir_p!(Path.join(repo, "lib"))

    File.write!(Path.join(repo, "mix.exs"), """
    defmodule DepProbe.MixProject do
      use Mix.Project
      def project, do: [app: :dep_probe, version: "0.1.0", deps: []]
    end
    """)

    File.write!(Path.join(repo, "lib/probe.ex"), """
    defmodule DepProbe do
      @value Application.compile_env(:dep_probe, :value, 1)
      def value, do: @value
    end
    """)

    git!(repo, ["init", "--quiet"])
    git!(repo, ["add", "."])

    git!(repo, [
      "-c",
      "user.name=Cache Test",
      "-c",
      "user.email=cache@example.com",
      "commit",
      "-qm",
      "fixture"
    ])

    project = Path.join(dir, "project")
    File.mkdir_p!(Path.join(project, "config"))
    cache = Path.join(dir, "cache")

    File.write!(Path.join(project, "mix.exs"), """
    defmodule CacheFixture.MixProject do
      use Mix.Project
      def project do
        [app: :cache_fixture, version: "0.1.0", deps: [{:dep_probe, git: #{inspect(repo)}}],
         tuist: [project: "test/cache", cache: [dependencies: [:dep_probe], remote: false, path: #{inspect(cache)}]]]
      end
    end
    """)

    File.write!(
      Path.join(project, "config/config.exs"),
      "import Config\nconfig :dep_probe, value: 1\n"
    )

    %{dir: dir, project: project}
  end

  for {bootstrap, partitions} <- [{:legacy, "2"}, {:ordinary, "2"}, {:ordinary, "1"}] do
    @tag timeout: 300_000, bootstrap: true
    test "the #{bootstrap} compile alias restores with #{partitions} dependency workers", %{
      project: project,
      dir: dir
    } do
      package = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
      mixfile = Path.join(project, "mix.exs")

      compile_alias =
        case unquote(bootstrap) do
          :legacy ->
            "&Code.eval_string(File.read!(#{inspect(Path.join(package, "compile.exs"))}), args: &1)"

          :ordinary ->
            inspect([
              "deps.compile tuist_ex --include-children",
              "deps.loadpaths --no-compile --no-deps-check",
              "tuist.compile"
            ])
        end

      contents =
        String.replace(
          File.read!(mixfile),
          "deps: [{:dep_probe,",
          "aliases: [compile: #{compile_alias}], deps: [{:tuist_ex, path: #{inspect(package)}, runtime: false}, {:dep_probe,"
        )

      compile_args =
        if unquote(bootstrap) == :ordinary,
          do: ["compile", "--warnings-as-errors"],
          else: ["compile"]

      File.write!(mixfile, contents)
      run_mix = &mix(project, &1, [{"MIX_OS_DEPS_COMPILE_PARTITION_COUNT", unquote(partitions)}])
      {output, status} = run_mix.(["deps.get"])
      assert status == 0, output
      {first, status} = run_mix.(compile_args)
      assert status == 0, first
      assert first =~ "Generated dep_probe app"
      assert [_snapshot] = File.ls!(Path.join(dir, "cache"))
      File.rm_rf!(Path.join(project, "_build"))
      {second, status} = run_mix.(compile_args)
      assert status == 0, second
      refute second =~ "Generated dep_probe app"

      assert File.exists?(
               Path.join(project, "_build/test/lib/dep_probe/ebin/Elixir.DepProbe.beam")
             )

      if unquote(bootstrap) == :ordinary do
        {output, status} =
          run_mix.([
            "tuist.test.build",
            "--no-upload",
            "--shard-reference",
            "bootstrap-regression"
          ])

        assert status != 0, output
        assert output =~ "No test files found"
        refute output =~ "Generated dep_probe app"
      end
    end
  end

  @tag timeout: 300_000, bootstrap: true
  test "cold shard preparation loads the SDK without compiling unrelated dependencies", %{
    project: project
  } do
    package = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: [{:dep_probe,",
        "deps: [{:tuist_ex, path: #{inspect(package)}, runtime: false}, {:dep_probe,"
      )
    )

    {output, status} = mix(project, ["deps.get"])
    assert status == 0, output

    {output, status} =
      mix(project, [
        "do",
        "deps.compile",
        "tuist_ex",
        "--include-children",
        "+",
        "deps.loadpaths",
        "--no-compile",
        "--no-deps-check",
        "+",
        "tuist.test",
        "--prepare-only"
      ])

    assert status != 0, output
    assert output =~ "require a shard index"
    refute output =~ "Generated dep_probe app"
  end

  test "the bundled compile script preserves cold and changed local dependencies", %{
    project: project
  } do
    local = Path.join(project, "local")
    sdk = Path.join(project, "sdk")
    File.mkdir_p!(sdk)

    File.write!(
      Path.join(sdk, "mix.exs"),
      "defmodule SDKFixture.MixProject do\nuse Mix.Project\ndef project, do: [app: :tuist_ex, version: \"0.1.0\", compilers: [:app], deps: []]\nend"
    )

    File.mkdir_p!(Path.join(local, "lib"))

    File.write!(
      Path.join(local, "mix.exs"),
      "defmodule LocalProbe.MixProject do\nuse Mix.Project\ndef project, do: [app: :local_probe, version: \"0.1.0\", deps: []]\nend"
    )

    File.write!(
      Path.join(local, "lib/local.ex"),
      "defmodule LocalProbe do\ndef value, do: 1\nend"
    )

    File.mkdir_p!(Path.join(project, "lib"))

    File.write!(
      Path.join(project, "lib/root.ex"),
      "defmodule CacheFixture do\n@value LocalProbe.value()\ndef value, do: @value\nend"
    )

    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: [{:dep_probe,",
        ~s|aliases: [compile: &Code.eval_string(File.read!(#{inspect(Path.join(Path.dirname(Mix.Project.project_file()), "compile.exs"))}), args: &1)], deps: [{:tuist_ex, path: "sdk"}, {:local_probe, path: "local"}, {:dep_probe,|
      )
    )

    ebin = :tuist_ex |> :code.lib_dir() |> to_string() |> Path.join("ebin")

    script = """
    Mix.start()
    Code.ensure_loaded!(Mix.Tasks.Tuist.Compile)
    Mix.Project.in_project(:cache_fixture, File.cwd!(), fn _ ->
      Mix.Task.run("loadconfig")
      Mix.Task.run("deps.get")
      Mix.Task.run("compile", ["--no-code-path-pruning"])
      IO.puts("LOCAL_VALUE=" <> Integer.to_string(LocalProbe.value()))
    end)
    """

    run = fn ->
      System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script],
        cd: project,
        stderr_to_stdout: true,
        env: [
          {"MIX_ENV", "dev"},
          {"MIX_BUILD_PATH", nil},
          {"MIX_DEPS_PATH", nil},
          {"MIX_OS_DEPS_COMPILE_PARTITION_COUNT", "1"},
          {"TUIST_URL", "http://localhost:1"},
          {"TUIST_TOKEN", "test"}
        ]
      )
    end

    {output, status} = run.()
    assert status == 0, output
    assert output =~ "LOCAL_VALUE=1"
    Process.sleep(1_100)

    File.write!(
      Path.join(local, "lib/local.ex"),
      "defmodule LocalProbe do\ndef value, do: 2\nend"
    )

    {output, status} = run.()
    assert status == 0, output
    assert output =~ "LOCAL_VALUE=2"
  end

  @tag timeout: 300_000, bootstrap: true
  test "a prepared shard does not re-enter the project's test preparation alias", %{
    project: project
  } do
    package = Mix.Project.project_file() |> Path.dirname() |> Path.expand()
    mixfile = Path.join(project, "mix.exs")
    mix_path = Path.join(project, "custom mix path")
    File.mkdir_p!(mix_path)

    File.write!(
      mixfile,
      mixfile
      |> File.read!()
      |> String.replace(
        "deps: [{:dep_probe,",
        ~s|aliases: [compile: &compile/1, test: ["fixture.prepare", "tuist.test"]], deps: [{:tuist_ex, path: #{inspect(package)}, runtime: false}, {:dep_probe,|
      )
      |> String.replace("\nend\n", """

        defp compile(args) do
          if "--no-compile" not in args do
            Mix.Task.run("deps.compile", ["tuist_ex", "--include-children"])
          end
          Mix.Task.run("deps.loadpaths", ["--no-compile", "--no-deps-check"])
          Mix.Task.run("tuist.compile", args)
        end
      end
      """)
    )

    File.mkdir_p!(Path.join(project, "lib"))

    File.write!(Path.join(project, "lib/prepare.ex"), """
    defmodule Mix.Tasks.Fixture.Prepare do
      use Mix.Task
      def run(_args), do: File.write!("preparation.marker", "ran")
    end
    """)

    File.mkdir_p!(Path.join(project, "test"))
    File.write!(Path.join(project, "test/test_helper.exs"), "ExUnit.start()")

    File.write!(Path.join(project, "test/prebuilt_test.exs"), """
    defmodule PrebuiltTest do
      use ExUnit.Case, async: true
      test "uses the prepared build", do: assert(DepProbe.value() == 1)
    end
    """)

    {output, status} = mix(project, ["deps.get"])
    assert status == 0, output
    {output, status} = mix(project, ["compile"])
    assert status == 0, output

    # Only the plan/report endpoints are replaced, inside this fresh VM. The
    # real wrapper, project alias and Mix test task run together.
    script = """
    Code.compiler_options(ignore_module_conflict: true)
    defmodule TuistEx.Analytics.HTTP do
      def project_request(:get, _, _, _), do: {:ok, %{"modules" => ["PrebuiltTest"]}}
      def submit_test_run(_, _), do: :ok
    end
    """

    run = fn args, mix_path ->
      script = script <> "Mix.Tasks.Tuist.Test.run(#{inspect(args)})"

      mix(project, ["run", "--no-compile", "--no-deps-check", "--no-start", "-e", script], [
        {"TUIST_GIT_UPLOAD_ENABLED", "false"},
        {"MIX_PATH", mix_path},
        {"EXPECTED_MIX_PATH", mix_path}
      ])
    end

    {output, status} =
      run.(
        [
          "--shard-index",
          "0",
          "--shard-reference",
          "regression",
          "--no-download",
          "--no-start"
        ],
        mix_path
      )

    assert status == 0, output
    assert output =~ "1 passed"
    refute File.exists?(Path.join(project, "preparation.marker"))
    refute output =~ "Compiling"
    refute output =~ "deps.compile running across"
    refute output =~ "==> "

    # Forwarded flags alone must not skip setup on an ordinary, unsharded run.
    {output, status} = run.(["--no-compile", "--no-deps-check", "--no-start"], mix_path)
    assert status == 0, output
    assert output =~ "1 passed"
    assert File.exists?(Path.join(project, "preparation.marker"))

    File.rm!(Path.join(project, "preparation.marker"))

    File.write!(Path.join(project, "test/prebuilt_test.exs"), """
    defmodule PrebuiltTest do
      use ExUnit.Case, async: true
      test "retries against the prepared build" do
        if File.exists?("retry.marker") do
          assert DepProbe.value() == 1
          assert System.get_env("MIX_PATH") == System.get_env("EXPECTED_MIX_PATH")
          assert System.get_env("TUIST_EX_RETRY_MIX_PATH") == nil
          File.write!("retry.arguments", :erlang.term_to_binary(System.argv()))
        else
          File.write!("retry.marker", "ran")
          flunk("retry once")
        end
      end
    end
    """)

    {output, status} =
      run.(
        [
          "--shard-index",
          "0",
          "--shard-reference",
          "regression",
          "--no-download",
          "--no-start",
          "--retries",
          "1"
        ],
        mix_path
      )

    assert status == 0, output
    assert output =~ "Retrying the failed tests"
    assert output =~ "1 passed"
    refute File.exists?(Path.join(project, "preparation.marker"))
    refute output =~ "Compiling"
    refute output =~ "deps.compile running across"

    for {arg, original_path} <- [{"+", mix_path}, {"slow,", nil}] do
      File.rm!(Path.join(project, "retry.marker"))
      File.rm!(Path.join(project, "retry.arguments"))

      {output, status} =
        run.(
          [
            "--shard-index",
            "0",
            "--shard-reference",
            "regression",
            "--no-download",
            "--no-start",
            "--retries",
            "1",
            "--include",
            arg
          ],
          original_path
        )

      assert status == 0, output
      assert output =~ "Retrying the failed tests"
      assert output =~ "1 passed"
      assert length(Regex.scan(~r/skips the project's test preparation alias/, output)) == 1

      arguments =
        project |> Path.join("retry.arguments") |> File.read!() |> :erlang.binary_to_term([:safe])

      assert ["--include", arg] in Enum.chunk_every(arguments, 2, 1, :discard)
      refute File.exists?(Path.join(project, "preparation.marker"))
      refute output =~ "Compiling"
      refute output =~ "Generated "
      refute output =~ "deps.compile running across"
    end
  end

  defp mix(project, args, environment \\ []) do
    System.cmd(System.find_executable("mix"), args,
      cd: project,
      stderr_to_stdout: true,
      env:
        [
          {"MIX_ENV", "test"},
          {"MIX_BUILD_PATH", nil},
          {"MIX_DEPS_PATH", nil},
          {"MIX_OS_DEPS_COMPILE_PARTITION_COUNT", "2"},
          {"TUIST_URL", "http://localhost:1"},
          {"TUIST_PROJECT", "test/cache"},
          {"TUIST_TOKEN", "test"}
        ] ++ environment
    )
  end

  test "rebar3 dependencies and their Mix dependents restore without compilation", %{
    project: project,
    dir: dir
  } do
    rebar_fixture!(project, dir)
    first = run!(project)
    assert first["value"] == 7
    assert Enum.all?(first["dependency_cache"], &(&1["outcome"] == "miss" and &1["reason"] == ""))

    assert Enum.sort(Enum.map(first["dependency_cache"], & &1["dependency"])) == [
             "dep_probe",
             "erlang_probe"
           ]

    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == 7
    assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "local_hit"))
    refute second["output"] =~ "Compiling"
    refute second["output"] =~ "Generated dep_probe"

    File.rm_rf!(Path.join(dir, "cache"))
    current = run!(project)
    assert Enum.all?(current["dependency_cache"], &(&1["reason"] == "up_to_date"))
  end

  test "rebar3 header changes invalidate the Erlang artifact and its Mix dependent", %{
    project: project,
    dir: dir
  } do
    rebar_fixture!(project, dir)
    first = run!(project)
    repo = Path.join(dir, "erlang_probe")
    File.write!(Path.join(repo, "include/value.hrl"), "-define(VALUE, 9).\n")
    commit!(repo)
    {output, status} = mix(project, ["deps.update", "erlang_probe"])
    assert status == 0, output
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == 9
    assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "miss"))

    refute Enum.map(first["dependency_cache"], & &1["key"]) ==
             Enum.map(second["dependency_cache"], & &1["key"])
  end

  test "Mix dependencies containing ordinary Erlang sources restore without recompiling", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    File.mkdir_p!(Path.join(repo, "src"))

    File.write!(
      Path.join(repo, "src/erlang_probe.erl"),
      "-module(erlang_probe).\n-export([value/0]).\nvalue() -> 7.\n"
    )

    File.write!(
      Path.join(repo, "lib/probe.ex"),
      "defmodule DepProbe do\n def value, do: :erlang_probe.value()\nend\n"
    )

    commit!(repo)
    assert [%{"outcome" => "miss", "reason" => ""}] = run!(project)["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == 7
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    refute second["output"] =~ "Compiling"
  end

  for manager <- [:mix, :rebar3] do
    @tag hash_audit: true, manager: manager
    test "#{manager} grammar outputs restore from a fresh source checkout", %{
      project: project,
      dir: dir,
      manager: manager
    } do
      if manager == :rebar3, do: rebar_fixture!(project, dir)
      repo = Path.join(dir, if(manager == :mix, do: "package", else: "erlang_probe"))
      File.mkdir_p!(Path.join(repo, "src"))

      File.write!(
        Path.join(repo, "src/cache_lexer.xrl"),
        "Definitions.\nD = [0-9]\nRules.\n{D}+ : {token, {number, TokenLine, list_to_integer(TokenChars)}}.\nErlang code.\n"
      )

      File.write!(
        Path.join(repo, "src/cache_parser.yrl"),
        "Nonterminals expr.\nTerminals number.\nRootsymbol expr.\nexpr -> number : element(3, '$1').\nErlang code.\n"
      )

      if manager == :mix do
        File.write!(
          Path.join(repo, "lib/probe.ex"),
          "defmodule DepProbe do\ndef value do\n{:ok, tokens, _} = :cache_lexer.string(~c\"42\")\n{:ok, value} = :cache_parser.parse(tokens)\nvalue\nend\nend"
        )
      else
        File.write!(
          Path.join(repo, "src/erlang_probe.erl"),
          "-module(erlang_probe).\n-export([value/0]).\nvalue() -> {ok, Tokens, _} = cache_lexer:string(\"42\"), {ok, Value} = cache_parser:parse(Tokens), Value.\n"
        )
      end

      commit!(repo)
      first = run!(project)
      assert first["value"] == 42

      assert Enum.all?(
               first["dependency_cache"],
               &(&1["outcome"] == "miss" and &1["reason"] == "")
             )

      File.rm_rf!(Path.join(project, "_build"))

      fetched =
        Path.join(project, if(manager == :mix, do: "deps/dep_probe", else: "deps/erlang_probe"))

      for name <- ["cache_lexer.erl", "cache_parser.erl"],
          do: File.rm!(Path.join([fetched, "src", name]))

      second = run!(project)
      assert second["value"] == 42
      assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "local_hit"))

      assert Enum.map(first["dependency_cache"], & &1["key"]) ==
               Enum.map(second["dependency_cache"], & &1["key"])

      refute second["output"] =~ "Compiling 1 file (.xrl)"
      refute second["output"] =~ "Compiling 1 file (.yrl)"
    end
  end

  @tag hash_audit: true
  test "rebar launcher identity follows Mix's parent resolution, not child command overrides", %{
    project: project,
    dir: dir
  } do
    rebar_fixture!(project, dir)
    package = Path.join(dir, "package")
    mixfile = Path.join(package, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "manager: :rebar3",
        ~s|manager: :rebar3, system_env: [{"MIX_REBAR3", "/missing-child-rebar-override"}]|
      )
    )

    commit!(package)
    first = run!(project)
    assert length(first["dependency_cache"]) == 2
    assert Enum.all?(first["dependency_cache"], &(&1["outcome"] == "miss" and &1["reason"] == ""))
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "local_hit"))

    assert Enum.map(first["dependency_cache"], & &1["key"]) ==
             Enum.map(second["dependency_cache"], & &1["key"])
  end

  test "rebar bare builds accept packaged app metadata, inert Makefiles and evaluated config scripts",
       %{project: project, dir: dir} do
    rebar_fixture!(project, dir)
    repo = Path.join(dir, "erlang_probe")
    File.mkdir_p!(Path.join(repo, "ebin"))

    File.rename!(
      Path.join(repo, "src/erlang_probe.app.src"),
      Path.join(repo, "ebin/erlang_probe.app")
    )

    File.write!(Path.join(repo, "Makefile"), "all:\n\tfalse\n")
    File.write!(Path.join(repo, "rebar.config.script"), "CONFIG.\n")
    commit!(repo)

    assert Enum.all?(
             run!(project)["dependency_cache"],
             &(&1["outcome"] == "miss" and &1["reason"] == "")
           )

    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == 7
    assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "local_hit"))
    refute second["output"] =~ "Compiling"
  end

  test "audited native builders restore generated priv executables without their producer source outputs",
       %{project: project, dir: dir} do
    native_fixture!(project, dir)
    first = run!(project)
    assert first["value"] == 7
    assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
    assert first["output"] =~ "NATIVE PROBE BUILD"
    File.rm_rf!(Path.join(project, "_build"))
    File.rm_rf!(Path.join(project, "deps/dep_probe/priv"))
    second = run!(project)
    assert second["value"] == 7
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    refute second["output"] =~ "NATIVE PROBE BUILD"
    assert File.lstat!(Path.join(project, "_build/dev/lib/dep_probe/priv")).type == :directory
    refute File.exists?(Path.join(project, "deps/dep_probe/priv/probe"))

    File.rm!(Path.join(project, "_build/dev/lib/dep_probe/priv/probe"))
    File.rm!(Path.join(project, "result.json"))
    repaired = run!(project)
    assert repaired["value"] == 7

    assert [%{"outcome" => "local_hit", "reason" => "", "key" => key}] =
             repaired["dependency_cache"]

    assert key != ""
    refute repaired["output"] =~ "NATIVE PROBE BUILD"
  end

  @tag hash_audit: true
  test "native builder environment uses dependency overrides rather than shadowed parent values",
       %{project: project, dir: dir} do
    native_fixture!(project, dir)
    mixfile = Path.join(project, "mix.exs")
    repo = Path.join(dir, "package")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "git: #{inspect(repo)}",
        ~s|git: #{inspect(repo)}, system_env: [{"PROBE_VALUE", "9"}]|
      )
    )

    first = run!(project, [{"PROBE_VALUE", "7"}])
    assert first["value"] == 9
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project, [{"PROBE_VALUE", "8"}])
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    assert hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]

    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), ~s|{"PROBE_VALUE", "9"}|, ~s|{"PROBE_VALUE", "10"}|)
    )

    third = run!(project)
    assert third["value"] == 10
    assert [%{"outcome" => "miss", "reason" => ""}] = third["dependency_cache"]
  end

  @tag hash_audit: true
  test "native builder keys include resolved custom project configuration", %{
    project: project,
    dir: dir
  } do
    native_fixture!(project, dir)
    repo = Path.join(dir, "package")
    mixfile = Path.join(repo, "mix.exs")

    File.write!(
      mixfile,
      File.read!(mixfile)
      |> String.replace(
        ~s|System.get_env("PROBE_VALUE", "7")|,
        "Integer.to_string(Mix.Project.config()[:native_value])"
      )
      |> String.replace(
        "deps: [], compilers:",
        "native_value: Application.get_env(:cache_hash_test, :flag, 7), deps: [], compilers:"
      )
    )

    commit!(repo)

    first = run!(project)
    assert first["value"] == 7
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      Path.join(project, "compiler-options.exs"),
      "Application.put_env(:cache_hash_test, :flag, 9)"
    )

    second = run!(project)
    assert second["value"] == 9
    assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]
    refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
  end

  test "native builder platform, environment, declared inputs and sources invalidate artifacts",
       %{project: project, dir: dir} do
    native_fixture!(project, dir)
    first = run!(project)
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project, [{"PROBE_VALUE", "9"}])
    assert second["value"] == 9
    assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]
    refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
    File.rm_rf!(Path.join(project, "_build"))
    File.write!(Path.join(project, "native-input.txt"), "changed toolchain input")
    third = run!(project, [{"PROBE_VALUE", "9"}])
    assert [%{"outcome" => "miss", "reason" => ""}] = third["dependency_cache"]
    refute hd(second["dependency_cache"])["key"] == hd(third["dependency_cache"])["key"]
    File.rm_rf!(Path.join(project, "_build"))
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), "native-test-platform-1", "native-test-platform-2")
    )

    fourth = run!(project, [{"PROBE_VALUE", "9"}])
    assert [%{"outcome" => "miss", "reason" => ""}] = fourth["dependency_cache"]
    refute hd(third["dependency_cache"])["key"] == hd(fourth["dependency_cache"])["key"]
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      Path.join(project, "deps/dep_probe/probe.c"),
      "#include <stdio.h>\nint main(void) { printf(\"11\"); }\n"
    )

    fifth = run!(project, [{"PROBE_VALUE", "9"}])
    assert fifth["value"] == 11
    assert [%{"outcome" => "miss", "reason" => ""}] = fifth["dependency_cache"]
  end

  test "downstream keys include native private artifacts even when upstream BEAMs and sources are unchanged",
       %{project: project, dir: dir} do
    native_fixture!(project, dir)
    consumer = Path.join(dir, "consumer")
    File.mkdir_p!(Path.join(consumer, "lib"))

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule Consumer.MixProject do
      use Mix.Project
      def project, do: [app: :env_reader, version: "0.1.0", deps: [{:dep_probe, git: #{inspect(Path.join(dir, "package"))}}]]
    end
    """)

    File.write!(
      Path.join(consumer, "lib/consumer.ex"),
      "defmodule EnvReader do\n@value DepProbe.value()\ndef value, do: @value\nend\n"
    )

    git!(consumer, ["init", "--quiet"])
    commit!(consumer)
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      File.read!(mixfile)
      |> String.replace(
        "deps: [{:dep_probe,",
        "deps: [{:env_reader, git: #{inspect(consumer)}}, {:dep_probe,"
      )
      |> String.replace("dependencies: [:dep_probe], ", "")
    )

    first = run!(project)
    assert first["env_reader_value"] == 7
    native = Path.join(project, "deps/dep_probe")

    {output, status} =
      System.cmd("cc", ["-DVALUE=9", "probe.c", "-o", "priv/probe"],
        cd: native,
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.rm_rf!(Path.join(project, "_build/dev/lib/env_reader"))
    second = run!(project)
    assert second["env_reader_value"] == 9

    assert %{"outcome" => "local_hit", "reason" => "up_to_date"} =
             Enum.find(second["dependency_cache"], &(&1["dependency"] == "dep_probe"))

    assert %{"outcome" => "miss"} =
             Enum.find(second["dependency_cache"], &(&1["dependency"] == "env_reader"))
  end

  test "audited Make builders materialize source-backed ebin outputs", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    File.rm!(Path.join(repo, "mix.exs"))
    File.rm_rf!(Path.join(repo, "lib"))
    File.mkdir_p!(Path.join(repo, "src"))
    File.mkdir_p!(Path.join(repo, "ebin"))

    File.write!(
      Path.join(repo, "src/Elixir.DepProbe.erl"),
      "-module('Elixir.DepProbe').\n-export([value/0]).\nvalue() -> ?VALUE.\n"
    )

    File.write!(
      Path.join(repo, "ebin/dep_probe.app"),
      "{application, dep_probe, [{vsn, \"0.1.0\"}, {modules, ['Elixir.DepProbe']}, {applications, [kernel, stdlib]}]}.\n"
    )

    File.write!(
      Path.join(repo, "Makefile"),
      "PROBE_MAKE_VALUE ?= 7\nall:\n\t@echo MAKE PROBE BUILD\n\terlc -DVALUE=$(PROBE_MAKE_VALUE) -o ebin src/Elixir.DepProbe.erl\n"
    )

    commit!(repo)
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "remote: false,",
        ~s(remote: false, builders: [dep_probe: [platform: "test-make-platform", outputs: ["ebin/Elixir.DepProbe.beam"], generated: ["ebin/Elixir.DepProbe.beam"]]],)
      )
    )

    first = run!(project)
    assert first["value"] == 7
    assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
    assert first["output"] =~ "MAKE PROBE BUILD"
    File.rm_rf!(Path.join(project, "_build"))
    File.rm!(Path.join(project, "deps/dep_probe/ebin/Elixir.DepProbe.beam"))
    second = run!(project)
    assert second["value"] == 7
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    refute second["output"] =~ "MAKE PROBE BUILD"
    assert File.lstat!(Path.join(project, "_build/dev/lib/dep_probe/ebin")).type == :directory

    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: [{:dep_probe, git:",
        ~s(deps: [{:dep_probe, compile: "make PROBE_MAKE_VALUE=9", git:)
      )
    )

    third = run!(project)
    assert third["value"] == 9
    assert [%{"outcome" => "miss", "reason" => ""}] = third["dependency_cache"]
    refute hd(first["dependency_cache"])["key"] == hd(third["dependency_cache"])["key"]
  end

  test "cache true automatically selects dependencies", %{project: project, dir: dir} do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      Regex.replace(
        ~r/cache: \[dependencies: \[:dep_probe\], remote: false, path: .*?\]/,
        File.read!(mixfile),
        "cache: true"
      )
    )

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        ~s(project: "test/cache"),
        ~s|project: "test/cache", url: "http://localhost:1"|
      )
    )

    cache_home = Path.join(dir, "cache-home")

    env = [
      {"HOME", Path.join(dir, "home")},
      {"XDG_CONFIG_HOME", Path.join(dir, "config-home")},
      {"XDG_CACHE_HOME", cache_home},
      {"TUIST_URL", "http://localhost:1"}
    ]

    assert [%{"outcome" => "miss"}] = run!(project, env)["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "local_hit"}] = run!(project, env)["dependency_cache"]
  end

  test "cache options automatically select dependencies without an allowlist", %{project: project} do
    mixfile = Path.join(project, "mix.exs")
    File.write!(mixfile, String.replace(File.read!(mixfile), "dependencies: [:dep_probe], ", ""))
    assert [%{"outcome" => "miss"}] = run!(project)["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "local_hit"}] = run!(project)["dependency_cache"]
  end

  test "excluded dependencies compile normally without cache lookups", %{project: project} do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), "dependencies: [:dep_probe]", "exclude: [:dep_probe]")
    )

    {output, status} = run(project)
    assert status == 0, output
    assert output =~ "Generated dep_probe app"
    refute File.exists?(Path.join(project, "result.json"))
    {output, status} = run(project)
    assert status == 0, output
    refute File.exists?(Path.join(project, "result.json"))
  end

  for cache <- ["false", "nil"] do
    test "cache #{cache} disables dependency caching", %{project: project} do
      mixfile = Path.join(project, "mix.exs")

      File.write!(
        mixfile,
        Regex.replace(
          ~r/cache: \[dependencies: \[:dep_probe\], remote: false, path: .*?\]/,
          File.read!(mixfile),
          "cache: #{unquote(cache)}"
        )
      )

      {output, status} = run(project)
      assert status == 0, output
      assert output =~ "Generated dep_probe app"
      refute File.exists?(Path.join(project, "result.json"))
    end
  end

  test "cold compiles populate the cache and a clean build restores a dependency", %{
    project: project
  } do
    first = run!(project)
    assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
    assert first["value"] == 1
    [published] = first["dependency_cache"]
    assert published["write_bytes"] > 0
    assert published["write_duration_us"] >= 0
    assert published["read_bytes"] == nil
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    [restored] = second["dependency_cache"]
    assert restored["read_bytes"] == published["write_bytes"]
    assert restored["read_duration_us"] >= 0
    assert restored["write_bytes"] == nil

    assert [%{"outcome" => "local_hit", "saved_duration_ms" => duration}] =
             second["dependency_cache"]

    assert is_integer(duration)
    assert second["value"] == 1
    refute second["output"] =~ "Compiling 1 file"
  end

  test "regex and struct configuration restores across VMs and invalidates on regex changes", %{
    project: project
  } do
    configure = fn pattern ->
      File.write!(
        Path.join(project, "config/config.exs"),
        "import Config\nconfig :dep_probe, value: 1, nested: %{patterns: [#{pattern}], uri: URI.parse(\"https://tuist.dev\")}\n"
      )
    end

    configure.("~r/priv\\/static/iu")
    first = run!(project)
    assert [%{"outcome" => "miss", "reason" => "", "key" => key}] = first["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert [%{"outcome" => "local_hit", "key" => ^key}] = second["dependency_cache"]

    for pattern <- ["~r/priv\\/assets/iu", "~r/priv\\/static/u"] do
      File.rm_rf!(Path.join(project, "_build"))
      configure.(pattern)
      result = run!(project)

      assert [%{"outcome" => "miss", "reason" => "", "key" => changed_key}] =
               result["dependency_cache"]

      refute changed_key == key
    end
  end

  for {field, expression, before_value, after_value} <- [
        {:description, ~s|Application.get_env(:cache_hash_test, :flag, "first")|, "first",
         "second"},
        {:application, ~s|[env: [choice: Application.get_env(:cache_hash_test, :flag, "first")]]|,
         "first", "second"},
        {:yecc_options, "[verbose: Application.get_env(:cache_hash_test, :flag, false)]", false,
         true},
        {:leex_options, "[verbose: Application.get_env(:cache_hash_test, :flag, false)]", false,
         true}
      ] do
    @tag hash_audit: true,
         field: field,
         expression: expression,
         before_value: before_value,
         after_value: after_value
    test "resolved #{field} is an artifact input, independently of source/config-file changes",
         ctx do
      repo = Path.join(ctx.dir, "package")
      mixfile = Path.join(repo, "mix.exs")
      source = File.read!(mixfile)

      source =
        if ctx.field == :application,
          do:
            String.replace(
              source,
              "def project,",
              "def application, do: #{ctx.expression}\n def project,"
            ),
          else: String.replace(source, "deps: []", "#{ctx.field}: #{ctx.expression}, deps: []")

      File.write!(mixfile, source)
      commit!(repo)
      control = Path.join(ctx.project, "compiler-options.exs")

      File.write!(
        control,
        "Application.put_env(:cache_hash_test, :flag, #{inspect(ctx.before_value)})"
      )

      first = run!(ctx.project)
      assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
      File.rm_rf!(Path.join(ctx.project, "_build"))

      File.write!(
        control,
        "Application.put_env(:cache_hash_test, :flag, #{inspect(ctx.after_value)})"
      )

      second = run!(ctx.project)
      assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]
      refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]

      {:ok, [{:application, :dep_probe, properties}]} =
        :file.consult(
          String.to_charlist(
            Path.join(ctx.project, "_build/dev/lib/dep_probe/ebin/dep_probe.app")
          )
        )

      if ctx.field == :description, do: assert(to_string(properties[:description]) == "second")
      if ctx.field == :application, do: assert(properties[:env][:choice] == "second")
    end
  end

  test "effective compile configuration invalidates a dependency", %{project: project} do
    first = run!(project)
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      Path.join(project, "config/config.exs"),
      "import Config\nconfig :dep_probe, value: 2\n"
    )

    second = run!(project)
    assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]

    refute first["dependency_cache"] |> hd() |> Map.fetch!("key") ==
             second["dependency_cache"] |> hd() |> Map.fetch!("key")

    assert second["value"] == 2
  end

  test "unselected fetched dependencies retain Mix's OS-worker batching", %{
    project: project,
    dir: dir
  } do
    repos =
      for app <- [:first_upstream, :second_upstream] do
        repo = Path.join(dir, Atom.to_string(app))
        File.mkdir_p!(Path.join(repo, "lib"))

        File.write!(
          Path.join(repo, "mix.exs"),
          "defmodule #{Macro.camelize(Atom.to_string(app))}.MixProject do\nuse Mix.Project\ndef project, do: [app: #{inspect(app)}, version: \"0.1.0\", deps: []]\nend"
        )

        File.write!(
          Path.join(repo, "lib/probe.ex"),
          "defmodule #{Macro.camelize(Atom.to_string(app))} do\ndef value, do: 1\nend"
        )

        git!(repo, ["init", "--quiet"])
        commit!(repo)
        {app, repo}
      end

    package = Path.join(dir, "package")

    deps =
      Enum.map_join(repos, ", ", fn {app, repo} -> "{#{inspect(app)}, git: #{inspect(repo)}}" end)

    mixfile = Path.join(package, "mix.exs")
    File.write!(mixfile, String.replace(File.read!(mixfile), "deps: []", "deps: [#{deps}]"))
    commit!(package)
    result = run!(project, [{"MIX_OS_DEPS_COMPILE_PARTITION_COUNT", "2"}])
    assert result["output"] =~ "mix deps.compile running across 2 OS processes"

    assert [%{"dependency" => "dep_probe", "outcome" => "miss", "reason" => ""}] =
             result["dependency_cache"]
  end

  test "application defaults do not prevent publication or change warm restore keys", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    mixfile = Path.join(repo, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "def project,",
        "def application, do: [env: [default_option: true]]\n  def project,"
      )
    )

    commit!(repo)
    first = run!(project)
    assert [%{"outcome" => "miss", "reason" => "", "key" => key}] = first["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "local_hit", "key" => ^key}] = run!(project)["dependency_cache"]
  end

  for {label, before_option, after_option, source} <- [
        {"system environment", ~s(system_env: [{"DEP_FEATURE", "on"}]),
         ~s(system_env: [{"DEP_FEATURE", "off"}]), ~s|System.get_env("DEP_FEATURE")|},
        {"Mix environment", "env: :dev", "env: :prod", "Atom.to_string(Mix.env())"}
      ] do
    @tag before_option: before_option, after_option: after_option, source: source
    test "dependency #{label} invalidates cached applications", %{
      project: project,
      dir: dir,
      before_option: before_option,
      after_option: after_option,
      source: source
    } do
      repo = Path.join(dir, "package")

      File.write!(
        Path.join(repo, "lib/probe.ex"),
        "defmodule DepProbe do\n@value #{source}\ndef value, do: @value\nend"
      )

      commit!(repo)
      mixfile = Path.join(project, "mix.exs")

      File.write!(
        mixfile,
        String.replace(
          File.read!(mixfile),
          "git: #{inspect(repo)}",
          "git: #{inspect(repo)}, #{before_option}"
        )
      )

      first = run!(project)
      File.rm_rf!(Path.join(project, "_build"))
      File.write!(mixfile, String.replace(File.read!(mixfile), before_option, after_option))
      second = run!(project)
      assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]
      refute first["value"] == second["value"]
      refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
    end
  end

  test "dependency configuration is evaluated under its effective system environment", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    mixfile = Path.join(repo, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        ~s(version: "0.1.0"),
        ~s|version: System.get_env("DEP_VERSION", "0.1.0")|
      )
    )

    commit!(repo)
    root_mixfile = Path.join(project, "mix.exs")

    File.write!(
      root_mixfile,
      String.replace(
        File.read!(root_mixfile),
        "git: #{inspect(repo)}",
        ~s|git: #{inspect(repo)}, system_env: [{"DEP_VERSION", "0.2.0"}]|
      )
    )

    first = run!(project)
    assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "local_hit"}] = run!(project)["dependency_cache"]
  end

  test "custom source compiler paths in ignored top-level directories bypass caching", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    mixfile = Path.join(repo, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: []",
        ~s(elixirc_paths: ["_build/generated"], deps: [])
      )
    )

    File.mkdir_p!(Path.join(repo, "_build/generated"))
    File.cp!(Path.join(repo, "lib/probe.ex"), Path.join(repo, "_build/generated/probe.ex"))
    commit!(repo)

    assert [%{"outcome" => "bypass", "reason" => "custom_compiler"}] =
             run!(project)["dependency_cache"]
  end

  test "current dependency outputs count as local hits without snapshot or transport measurements",
       %{
         project: project,
         dir: dir
       } do
    run!(project)
    File.rm_rf!(Path.join(dir, "cache"))
    File.rm!(Path.join(project, "result.json"))

    result = run!(project)

    assert [
             %{
               "outcome" => "local_hit",
               "reason" => "up_to_date",
               "key" => key,
               "duration_ms" => duration,
               "saved_duration_ms" => nil
             } = hit
           ] = result["dependency_cache"]

    assert key == ""
    assert duration >= 0
    assert result["files"] == []
    refute result["output"] =~ "Generated dep_probe app"
    refute File.exists?(Path.join(dir, "cache"))
    refute File.exists?(Path.join(project, "remote-opened"))

    for field <-
          ~w(read_bytes read_duration_us read_source write_bytes write_duration_us write_source) do
      assert is_nil(hit[field])
    end
  end

  test "observing current outputs does not read source contents or hash declared inputs", %{
    project: project
  } do
    run!(project)
    source = Path.join(project, "deps/dep_probe/lib/probe.ex")
    File.chmod!(source, 0o000)
    on_exit(fn -> File.chmod(source, 0o644) end)
    mixfile = Path.join(project, "mix.exs")
    File.ln_s!("mix.exs", Path.join(project, "external-input"))

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "dependencies: [:dep_probe]",
        ~s(dependencies: [:dep_probe], inputs: ["external-input"])
      )
    )

    assert [%{"outcome" => "local_hit", "reason" => "up_to_date", "key" => ""}] =
             run!(project)["dependency_cache"]
  end

  test "supported outputs compiled before caching was enabled also count as local hits", %{
    project: project,
    dir: dir
  } do
    mixfile = Path.join(project, "mix.exs")
    contents = File.read!(mixfile)

    File.write!(
      mixfile,
      String.replace(contents, "dependencies: [:dep_probe]", "exclude: [:dep_probe]")
    )

    {output, status} = run(project)
    assert status == 0, output
    refute File.exists?(Path.join(project, "result.json"))
    File.write!(mixfile, contents)

    assert [%{"outcome" => "local_hit", "reason" => "up_to_date"}] =
             run!(project)["dependency_cache"]

    refute File.exists?(Path.join(dir, "cache"))
    refute File.exists?(Path.join(project, "remote-opened"))
  end

  test "changed locked inputs require compilation instead of an up-to-date local hit", %{
    project: project,
    dir: dir
  } do
    first = run!(project)
    repo = Path.join(dir, "package")
    File.write!(Path.join(repo, "lib/probe.ex"), "defmodule DepProbe do\ndef value, do: 3\nend\n")
    commit!(repo)
    {output, status} = mix(project, ["deps.update", "dep_probe"])
    assert status == 0, output

    second = run!(project)
    assert [%{"outcome" => "miss"}] = second["dependency_cache"]
    assert second["value"] == 3
    refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
  end

  test "current dependencies with unsupported sources are not counted as local hits", %{
    project: project,
    dir: dir
  } do
    File.write!(Path.join(dir, "package/native.c"), "")
    commit!(Path.join(dir, "package"))

    assert [%{"outcome" => "bypass", "reason" => "custom_compiler"}] =
             run!(project)["dependency_cache"]

    File.rm!(Path.join(project, "result.json"))
    {output, status} = run(project)
    assert status == 0, output
    refute File.exists?(Path.join(project, "result.json"))
  end

  test "current dependencies with missing BEAM outputs are not counted as local hits", %{
    project: project
  } do
    run!(project)
    File.rm!(Path.join(project, "result.json"))
    File.rm!(Path.join(project, "_build/dev/lib/dep_probe/ebin/Elixir.DepProbe.beam"))
    {output, status} = run(project)
    assert status == 0, output
    refute File.exists?(Path.join(project, "result.json"))
  end

  test "allowlisted current path dependencies do not report idle builds", %{
    project: project,
    dir: dir
  } do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "git: #{inspect(Path.join(dir, "package"))}",
        "path: #{inspect(Path.join(dir, "package"))}"
      )
    )

    run!(project)
    File.rm!(Path.join(project, "result.json"))
    {output, status} = run(project)
    assert status == 0, output
    refute File.exists?(Path.join(project, "result.json"))
  end

  test "missing application metadata is rejected and healed rather than counted as a hit", %{
    project: project,
    dir: dir
  } do
    first = run!(project)
    key = hd(first["dependency_cache"])["key"]
    entry = Path.join([dir, "cache", key])
    manifest_path = Path.join(entry, "manifest.json")
    manifest = JSON.decode!(File.read!(manifest_path))
    files = Enum.reject(manifest["files"], &(&1["path"] == "ebin/dep_probe.app"))
    File.write!(manifest_path, JSON.encode!(Map.put(manifest, "files", files)))
    File.rm!(Path.join(entry, "files/ebin/dep_probe.app"))
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "miss", "reason" => ""}] = run!(project)["dependency_cache"]
    assert File.regular?(Path.join(entry, "files/ebin/dep_probe.app"))
    File.rm_rf!(Path.join(project, "_build"))
    assert [%{"outcome" => "local_hit"}] = run!(project)["dependency_cache"]
  end

  test "source changes invalidate even when the lock is unchanged", %{project: project} do
    first = run!(project)
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      Path.join(project, "deps/dep_probe/lib/probe.ex"),
      "defmodule DepProbe do\n def value, do: 3\nend\n"
    )

    second = run!(project)
    assert [%{"outcome" => "miss"}] = second["dependency_cache"]
    assert second["value"] == 3
    refute hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
  end

  test "portable reuse is explicit and restored resource links target the new checkout", %{
    project: project,
    dir: dir
  } do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "dependencies: [:dep_probe]",
        "portable: true, dependencies: [:dep_probe]"
      )
    )

    first = run!(project)
    assert [%{"outcome" => "miss"}] = first["dependency_cache"]
    relocated = Path.join(dir, "relocated")
    File.cp_r!(project, relocated)
    File.rm_rf!(Path.join(relocated, "_build"))
    second = run!(relocated)
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    assert second["value"] == 1
  end

  test "unmodeled source links and custom compiler inputs bypass caching", %{project: project} do
    run!(project)
    File.rm_rf!(Path.join(project, "_build"))
    File.ln_s!(Path.join(project, "mix.exs"), Path.join(project, "deps/dep_probe/external-input"))

    assert [%{"outcome" => "bypass", "reason" => "unmodeled_input"}] =
             run!(project)["dependency_cache"]

    File.rm!(Path.join(project, "deps/dep_probe/external-input"))
    File.rm_rf!(Path.join(project, "_build"))
    File.write!(Path.join(project, "deps/dep_probe/native.c"), "")

    assert [%{"outcome" => "bypass", "reason" => "custom_compiler"}] =
             run!(project)["dependency_cache"]
  end

  for source <- [:git, :path] do
    @tag source: source
    test "#{source} upstream changes cannot restore stale dependent artifacts", %{
      project: project,
      dir: dir,
      source: source
    } do
      upstream = Path.join(dir, "upstream")
      File.mkdir_p!(Path.join(upstream, "lib"))

      File.write!(
        Path.join(upstream, "mix.exs"),
        "defmodule Upstream.MixProject do\nuse Mix.Project\ndef project, do: [app: :upstream, version: \"0.1.0\", deps: []]\nend\n"
      )

      File.write!(
        Path.join(upstream, "lib/upstream.ex"),
        "defmodule Upstream do\ndef value, do: 11\nend\n"
      )

      git!(upstream, ["init", "--quiet"])
      git!(upstream, ["add", "."])

      git!(upstream, [
        "-c",
        "user.name=Cache Test",
        "-c",
        "user.email=cache@example.com",
        "commit",
        "-qm",
        "fixture"
      ])

      repo = Path.join(dir, "package")
      mixfile = Path.join(repo, "mix.exs")

      File.write!(
        mixfile,
        String.replace(
          File.read!(mixfile),
          "deps: []",
          "deps: [{:upstream, #{source}: #{inspect(upstream)}}]"
        )
      )

      File.write!(
        Path.join(repo, "lib/probe.ex"),
        "defmodule DepProbe do\n@value Upstream.value()\ndef value, do: @value\nend\n"
      )

      git!(repo, ["add", "."])

      git!(repo, [
        "-c",
        "user.name=Cache Test",
        "-c",
        "user.email=cache@example.com",
        "commit",
        "-qm",
        "upstream"
      ])

      root_mixfile = Path.join(project, "mix.exs")

      File.write!(
        root_mixfile,
        String.replace(
          File.read!(root_mixfile),
          "dependencies: [:dep_probe]",
          "dependencies: [:upstream, :dep_probe]"
        )
      )

      first = run!(project)
      assert first["value"] == 11

      if source == :path do
        File.rm_rf!(Path.join(project, "_build/dev/lib/dep_probe"))
        Process.sleep(1_100)
      else
        File.rm_rf!(Path.join(project, "_build"))
      end

      source_file =
        if source == :path,
          do: Path.join(upstream, "lib/upstream.ex"),
          else: Path.join(project, "deps/upstream/lib/upstream.ex")

      File.write!(
        source_file,
        "defmodule Upstream do\ndef value, do: 22\nend\n"
      )

      second = run!(project)
      assert second["value"] == 22

      if source == :path do
        assert Enum.all?(
                 second["dependency_cache"],
                 &(&1["outcome"] == "bypass" && &1["reason"] == "local_dependency")
               )
      else
        assert Enum.all?(second["dependency_cache"], &(&1["outcome"] == "miss"))
        first_parent = Enum.find(first["dependency_cache"], &(&1["dependency"] == "dep_probe"))
        second_parent = Enum.find(second["dependency_cache"], &(&1["dependency"] == "dep_probe"))
        refute first_parent["key"] == second_parent["key"]
      end
    end
  end

  test "local snapshots restore without discovering the remote cache", %{project: project} do
    run!(project)
    mixfile = Path.join(project, "mix.exs")
    File.write!(mixfile, String.replace(File.read!(mixfile), "remote: false", "remote: true"))
    File.rm_rf!(Path.join(project, "_build"))

    assert [%{"outcome" => "local_hit", "read_source" => "local"}] =
             run!(project)["dependency_cache"]

    refute File.exists?(Path.join(project, "remote-opened"))

    File.rm!(Path.join(project, "result.json"))

    assert [%{"outcome" => "local_hit", "reason" => "up_to_date"}] =
             run!(project)["dependency_cache"]

    refute File.exists?(Path.join(project, "remote-opened"))
  end

  @tag hash_audit: true
  test "global input declaration order and duplicates do not change artifact keys", %{
    project: project
  } do
    File.write!(Path.join(project, "extra-input"), "input")
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "dependencies: [:dep_probe]",
        ~s|dependencies: [:dep_probe], inputs: ["extra-input", "missing-input", "extra-input"]|
      )
    )

    first = run!(project)
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        ~s|["extra-input", "missing-input", "extra-input"]|,
        ~s|["missing-input", "extra-input"]|
      )
    )

    second = run!(project)
    assert [%{"outcome" => "local_hit"}] = second["dependency_cache"]
    assert hd(first["dependency_cache"])["key"] == hd(second["dependency_cache"])["key"]
  end

  test "declared environment and file inputs invalidate cached dependencies", %{project: project} do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "dependencies: [:dep_probe]",
        ~s(dependencies: [:dep_probe], inputs: ["extra.txt"], env: ["CACHE_TEST_INPUT"])
      )
    )

    first = run!(project, [{"CACHE_TEST_INPUT", "one"}])
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project, [{"CACHE_TEST_INPUT", "two"}])
    File.rm_rf!(Path.join(project, "_build"))
    File.write!(Path.join(project, "extra.txt"), "new external input")
    third = run!(project, [{"CACHE_TEST_INPUT", "two"}])
    assert [%{"outcome" => "miss", "key" => first_key}] = first["dependency_cache"]
    assert [%{"outcome" => "miss", "key" => second_key}] = second["dependency_cache"]
    assert [%{"outcome" => "miss", "key" => third_key}] = third["dependency_cache"]
    refute first_key == second_key
    refute second_key == third_key
  end

  test "portable keys still distinguish Mix environments and targets", %{project: project} do
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), "remote: false", "remote: false, portable: true")
    )

    first = run!(project)
    second = run!(project, [{"MIX_ENV", "test"}])
    third = run!(project, [{"MIX_TARGET", "embedded"}])

    keys =
      for result <- [first, second, third] do
        assert [%{"outcome" => "miss", "key" => key}] = result["dependency_cache"]
        key
      end

    assert length(Enum.uniq(keys)) == 3
  end

  test "custom global tracers bypass caching rather than skipping their side effects", %{
    project: project
  } do
    File.write!(Path.join(project, "compiler-options.exs"), """
    defmodule CustomTracer do
      def trace(_, _), do: :ok
    end
    Code.put_compiler_option(:tracers, [CustomTracer])
    """)

    assert [%{"outcome" => "bypass", "reason" => "custom_compiler"}] =
             run!(project)["dependency_cache"]
  end

  test "standard Erlang compiler environment is automatically part of the key", %{
    project: project
  } do
    first = run!(project, [{"ERL_COMPILER_OPTIONS", "[]"}])
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project, [{"ERL_COMPILER_OPTIONS", "[deterministic]"}])
    assert [%{"outcome" => "miss", "key" => first_key}] = first["dependency_cache"]
    assert [%{"outcome" => "miss", "key" => second_key}] = second["dependency_cache"]
    refute first_key == second_key
  end

  test "VM-wide compiler options are part of the key", %{project: project} do
    first = run!(project)
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      Path.join(project, "compiler-options.exs"),
      "Code.put_compiler_option(:debug_info, false)"
    )

    second = run!(project)
    assert [%{"outcome" => "miss", "key" => first_key}] = first["dependency_cache"]
    assert [%{"outcome" => "miss", "key" => second_key}] = second["dependency_cache"]
    refute first_key == second_key
  end

  test "compile.all aliases bypass restoration and publication", %{project: project, dir: dir} do
    repo = Path.join(dir, "package")
    mixfile = Path.join(repo, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: []",
        ~s(aliases: ["compile.all": ["compile.all"]], deps: [])
      )
    )

    commit!(repo)

    for _ <- 1..2 do
      File.rm_rf!(Path.join(project, "_build"))
      result = run!(project)
      assert result["value"] == 1

      assert [%{"outcome" => "bypass", "reason" => "custom_compiler"}] =
               result["dependency_cache"]

      assert result["output"] =~ "Generated dep_probe app"
      refute File.exists?(Path.join(dir, "cache"))
    end
  end

  test "new unsupported source paths after compilation fail open without publication", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    File.write!(Path.join(repo, "README.md"), "source resource")

    File.write!(Path.join(repo, "lib/probe.ex"), """
    defmodule DepProbe do
      File.mkdir_p!("src")
      File.ln_s!("../README.md", "src/link")
      def value, do: 1
    end
    """)

    commit!(repo)
    result = run!(project)
    assert result["value"] == 1
    assert [%{"outcome" => "miss", "reason" => "inputs_changed"}] = result["dependency_cache"]
    assert File.ls!(Path.join(dir, "cache")) == []
  end

  @tag hash_audit: true
  test "local restore reconciles inputs after staging, before installing cached code", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    external = Path.join(project, "external-input")
    File.write!(external, "before")
    mixfile = Path.join(repo, "mix.exs")

    application = """
    def application do
      pattern = Mix.Project.app_path() <> ".tuist-restore-*/ebin/*.beam"
      if Path.wildcard(pattern) != [], do: File.write!(#{inspect(external)}, "after")
      []
    end
    """

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), "def project,", application <> "\ndef project,")
    )

    File.write!(
      Path.join(repo, "lib/probe.ex"),
      "defmodule DepProbe do\n@value File.read!(#{inspect(external)})\ndef value, do: @value\nend"
    )

    commit!(repo)
    root_mixfile = Path.join(project, "mix.exs")

    File.write!(
      root_mixfile,
      String.replace(
        File.read!(root_mixfile),
        "dependencies: [:dep_probe]",
        "dependencies: [:dep_probe], inputs: [#{inspect(external)}]"
      )
    )

    first = run!(project)
    assert first["value"] == "before"
    assert [%{"outcome" => "miss", "reason" => ""}] = first["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == "after"
    assert [%{"outcome" => "miss", "reason" => "", "key" => new_key}] = second["dependency_cache"]
    refute new_key == hd(first["dependency_cache"])["key"]
    File.rm_rf!(Path.join(project, "_build"))
    third = run!(project)
    assert third["value"] == "after"
    assert [%{"outcome" => "local_hit", "key" => ^new_key}] = third["dependency_cache"]
  end

  @tag hash_audit: true
  test "publication reconciles inputs after copying artifact resources", %{
    project: project,
    dir: dir
  } do
    repo = Path.join(dir, "package")
    external = Path.join(project, "external-input")
    File.write!(external, "before")
    mixfile = Path.join(repo, "mix.exs")
    pattern = Path.join([dir, "cache", "*.tuist-publish-*", "files", "ebin", "*.beam"])

    application = """
    def application do
      if Path.wildcard(#{inspect(pattern)}) != [], do: File.write!(#{inspect(external)}, "after")
      []
    end
    """

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), "def project,", application <> "\ndef project,")
    )

    File.write!(
      Path.join(repo, "lib/probe.ex"),
      "defmodule DepProbe do\n@value File.read!(#{inspect(external)})\ndef value, do: @value\nend"
    )

    commit!(repo)
    root_mixfile = Path.join(project, "mix.exs")

    File.write!(
      root_mixfile,
      String.replace(
        File.read!(root_mixfile),
        "dependencies: [:dep_probe]",
        "dependencies: [:dep_probe], inputs: [#{inspect(external)}]"
      )
    )

    first = run!(project)
    assert first["value"] == "before"
    assert [%{"outcome" => "miss", "reason" => "inputs_changed"}] = first["dependency_cache"]
    assert File.ls!(Path.join(dir, "cache")) == []
    File.rm_rf!(Path.join(project, "_build"))
    second = run!(project)
    assert second["value"] == "after"
    assert [%{"outcome" => "miss", "reason" => ""}] = second["dependency_cache"]
  end

  test "changes to declared external inputs during compilation prevent publication", %{
    project: project,
    dir: dir
  } do
    mixfile = Path.join(project, "mix.exs")
    external = Path.join(dir, "changing-input")
    File.write!(external, "before")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "dependencies: [:dep_probe]",
        "dependencies: [:dep_probe], inputs: [#{inspect(external)}]"
      )
    )

    source = Path.join(project, "deps/dep_probe/lib/probe.ex")
    run!(project)
    existing = File.ls!(Path.join(dir, "cache"))
    File.rm_rf!(Path.join(project, "_build"))

    File.write!(
      source,
      "defmodule DepProbe do\nFile.write!(#{inspect(external)}, \"after\")\ndef value, do: 1\nend"
    )

    assert [%{"outcome" => "miss", "reason" => "inputs_changed"}] =
             run!(project)["dependency_cache"]

    assert File.ls!(Path.join(dir, "cache")) == existing
  end

  test "each dependency uses the current inputs after an earlier compile changes them", %{
    project: project,
    dir: dir
  } do
    external = Path.join(dir, "compile-input")
    File.write!(external, "before")
    package = Path.join(dir, "package")

    File.write!(Path.join(package, "lib/probe.ex"), """
    defmodule DepProbe do
      @value File.read!(#{inspect(external)})
      def value, do: @value
    end
    """)

    git!(package, ["add", "."])

    git!(package, [
      "-c",
      "user.name=Cache Test",
      "-c",
      "user.email=cache@example.com",
      "commit",
      "-qm",
      "file input"
    ])

    reader = Path.join(dir, "reader")
    File.mkdir_p!(Path.join(reader, "lib"))

    File.write!(Path.join(reader, "mix.exs"), """
    defmodule EnvReader.MixProject do
      use Mix.Project
      def project, do: [app: :env_reader, version: "0.1.0", deps: []]
    end
    """)

    File.write!(Path.join(reader, "lib/reader.ex"), """
    defmodule EnvReader do
      @value File.read!(#{inspect(external)})
      def value, do: @value
    end
    """)

    git!(reader, ["init", "--quiet"])
    git!(reader, ["add", "."])

    git!(reader, [
      "-c",
      "user.name=Cache Test",
      "-c",
      "user.email=cache@example.com",
      "commit",
      "-qm",
      "fixture"
    ])

    mixfile = Path.join(project, "mix.exs")

    content =
      File.read!(mixfile)
      |> String.replace(
        "deps: [{:dep_probe, git: #{inspect(Path.join(dir, "package"))}}]",
        "deps: [{:dep_probe, git: #{inspect(Path.join(dir, "package"))}}, {:env_reader, git: #{inspect(reader)}}]"
      )
      |> String.replace(
        "dependencies: [:dep_probe]",
        "dependencies: [:dep_probe, :env_reader], inputs: [#{inspect(external)}]"
      )

    File.write!(mixfile, content)
    first = run!(project)
    assert first["value"] == "before"
    assert first["env_reader_value"] == "before"
    [mutator, consumer] = first["dependency_cache"]
    File.rm_rf!(Path.join(project, "_build"))

    {path, module} =
      Map.fetch!(
        %{
          "dep_probe" => {"deps/dep_probe/lib/probe.ex", "DepProbe"},
          "env_reader" => {"deps/env_reader/lib/reader.ex", "EnvReader"}
        },
        mutator["dependency"]
      )

    File.write!(Path.join(project, path), """
    defmodule #{module} do
      File.write!(#{inspect(external)}, "after")
      def value, do: 1
    end
    """)

    result = run!(project)
    field = if consumer["dependency"] == "dep_probe", do: "value", else: "env_reader_value"
    assert result[field] == "after"

    assert %{"outcome" => "miss", "reason" => "inputs_changed"} =
             Enum.find(result["dependency_cache"], &(&1["dependency"] == mutator["dependency"]))

    assert %{"outcome" => "miss", "reason" => ""} =
             Enum.find(result["dependency_cache"], &(&1["dependency"] == consumer["dependency"]))
  end

  test "cache directories inside dependency outputs are not modeled", %{
    project: project,
    dir: dir
  } do
    mixfile = Path.join(project, "mix.exs")
    unsafe_root = Path.join(project, "_build/dev/lib/dep_probe/cache")

    File.write!(
      mixfile,
      String.replace(File.read!(mixfile), inspect(Path.join(dir, "cache")), inspect(unsafe_root))
    )

    assert [%{"outcome" => "bypass", "reason" => "unmodeled_input"}] =
             run!(project)["dependency_cache"]

    refute File.exists?(unsafe_root)
  end

  test "compiler failures remain failures and do not publish", %{project: project, dir: dir} do
    run!(project)
    File.rm_rf!(Path.join(project, "_build"))
    File.write!(Path.join(project, "deps/dep_probe/lib/probe.ex"), "not valid elixir (")
    {_output, status} = run(project)
    assert status != 0
    assert length(File.ls!(Path.join(dir, "cache"))) == 1
  end

  defp native_fixture!(project, dir) do
    repo = Path.join(dir, "package")

    File.write!(Path.join(repo, "mix.exs"), """
    defmodule Mix.Tasks.Compile.NativeProbe do
      use Mix.Task.Compiler
      def run(_) do
        IO.puts("NATIVE PROBE BUILD")
        File.mkdir_p!("priv")
        Mix.Project.build_structure()
        {output, status} = System.cmd("cc", ["-DVALUE=" <> System.get_env("PROBE_VALUE", "7"), "probe.c", "-o", "priv/probe"], stderr_to_stdout: true)
        if status != 0, do: Mix.raise(output)
        File.rm("priv/probe-link")
        File.ln_s!("probe", "priv/probe-link")
        {:ok, []}
      end
    end
    defmodule DepProbe.MixProject do
      use Mix.Project
      def project, do: [app: :dep_probe, version: "0.1.0", deps: [], compilers: [:native_probe] ++ Mix.compilers()]
    end
    """)

    File.write!(
      Path.join(repo, "probe.c"),
      "#include <stdio.h>\nint main(void) { printf(\"%d\", VALUE); }\n"
    )

    File.write!(Path.join(repo, "lib/probe.ex"), """
    defmodule DepProbe do
      def value do
        {output, 0} = System.cmd(Application.app_dir(:dep_probe, "priv/probe-link"), [])
        String.to_integer(output)
      end
    end
    """)

    commit!(repo)
    mixfile = Path.join(project, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "remote: false,",
        ~s(remote: false, builders: [dep_probe: [platform: "native-test-platform-1", outputs: ["priv/probe", "priv/probe-link"], generated: ["priv/probe", "priv/probe-link"], env: ["PROBE_VALUE"], tools: ["cc"], inputs: ["native-input.txt"]]],)
      )
    )

    File.write!(Path.join(project, "native-input.txt"), "toolchain input")
  end

  defp rebar_fixture!(project, dir) do
    repo = Path.join(dir, "erlang_probe")
    File.mkdir_p!(Path.join(repo, "src"))
    File.mkdir_p!(Path.join(repo, "include"))
    File.write!(Path.join(repo, "rebar.config"), "{erl_opts, [debug_info]}.\n{deps, []}.\n")
    File.write!(Path.join(repo, "include/value.hrl"), "-define(VALUE, 7).\n")

    File.write!(
      Path.join(repo, "src/erlang_probe.erl"),
      "-module(erlang_probe).\n-export([value/0]).\n-include(\"value.hrl\").\nvalue() -> ?VALUE.\n"
    )

    File.write!(
      Path.join(repo, "src/erlang_probe.app.src"),
      "{application, erlang_probe, [{vsn, \"0.1.0\"}, {modules, []}, {applications, [kernel, stdlib]}]}.\n"
    )

    git!(repo, ["init", "--quiet"])
    commit!(repo)
    package = Path.join(dir, "package")
    mixfile = Path.join(package, "mix.exs")

    File.write!(
      mixfile,
      String.replace(
        File.read!(mixfile),
        "deps: []",
        "deps: [{:erlang_probe, git: #{inspect(repo)}, manager: :rebar3}]"
      )
    )

    File.write!(
      Path.join(package, "lib/probe.ex"),
      "defmodule DepProbe do\n@value :erlang_probe.value()\ndef value, do: @value\nend\n"
    )

    commit!(package)
    root = Path.join(project, "mix.exs")
    File.write!(root, String.replace(File.read!(root), "dependencies: [:dep_probe], ", ""))
  end

  defp run!(project, env \\ []) do
    {output, status} = run(project, env)
    assert status == 0, output
    assert File.exists?(Path.join(project, "result.json")), output
    result = JSON.decode!(File.read!(Path.join(project, "result.json")))
    Map.put(result, "output", output)
  end

  defp run(project, env \\ []) do
    ebin = :tuist_ex |> :code.lib_dir() |> to_string() |> Path.join("ebin")

    script = """
    Mix.start()
    Mix.Project.in_project(:cache_fixture, File.cwd!(), fn _ ->
      Mix.Task.run("loadconfig")
      Mix.Task.run("deps.get")
      if File.exists?("compiler-options.exs"), do: Code.eval_file("compiler-options.exs")
      {:ok, reporter} = TuistEx.Analytics.CompileReporter.start(sampler: nil,
        shell: &IO.puts/1, environment: fn _ -> nil end,
        submit: fn payload, _ ->
          payload = Map.put(payload, :value, DepProbe.value())
          payload = if Code.ensure_loaded?(EnvReader), do: Map.put(payload, :env_reader_value, EnvReader.value()), else: payload
          File.write!("result.json", JSON.encode!(payload))
          :ok
        end)
      TuistEx.DependencyCache.prepare([], reporter,
        environment: fn key ->
          File.write!("remote-opened", key)
          nil
        end)
      Mix.Task.run("compile")
      Code.prepend_path(#{inspect(ebin)})
      TuistEx.Analytics.CompileReporter.finish(reporter)
    end)
    """

    System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script],
      cd: project,
      env:
        [
          {"MIX_ENV", "dev"},
          {"MIX_TARGET", "host"},
          {"MIX_BUILD_PATH", nil},
          {"MIX_DEPS_PATH", nil},
          {"MIX_OS_DEPS_COMPILE_PARTITION_COUNT", "1"}
        ] ++ env,
      stderr_to_stdout: true
    )
  end

  defp commit!(repo) do
    git!(repo, ["add", "."])

    git!(repo, [
      "-c",
      "user.name=Cache Test",
      "-c",
      "user.email=cache@example.com",
      "commit",
      "-qm",
      "regression"
    ])
  end

  defp git!(dir, args) do
    {output, status} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    assert status == 0, output
  end
end
