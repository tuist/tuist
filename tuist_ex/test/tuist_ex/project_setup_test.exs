defmodule TuistEx.ProjectSetupTest do
  use ExUnit.Case, async: true

  alias TuistEx.ProjectSetup

  @bootstrap [
    "deps.compile tuist_ex --include-children",
    "deps.loadpaths --no-compile --no-deps-check",
    "tuist.compile"
  ]

  test "configures a simple project without evaluation code" do
    source = """
    defmodule Demo.MixProject do
      use Mix.Project
      def project do
        [app: :demo, version: "0.1.0"]
      end
    end
    """

    assert {:ok, updated} = ProjectSetup.configure(source, [], project: "account/demo")
    assert updated =~ "deps.compile tuist_ex --include-children"
    assert updated =~ ~s(project: "account/demo")
    assert updated =~ "cache: true"
    assert updated =~ ~s(test: "tuist.test")
    refute updated =~ "Code.eval"
    assert {:ok, _} = Code.string_to_quoted(updated)
  end

  test "preserves dynamic aliases, other settings and comments" do
    source = """
    defmodule Demo.MixProject do
      use Mix.Project
      def project do
        # Keep this comment: café
        [app: :demo, aliases: aliases(), tuist: [url: "http://localhost:8080", cache: [remote: false]]]
      end
      defp aliases, do: [test: ["ecto.create", "test"], compile: "tuist.compile"]
    end
    """

    config = [
      aliases: [test: ["ecto.create", "test"], compile: "tuist.compile"],
      tuist: [url: "http://localhost:8080", cache: [remote: false]]
    ]

    assert {:ok, updated} = ProjectSetup.configure(source, config, project: "account/demo")
    assert updated =~ "Keyword.merge(aliases(),"
    assert updated =~ "Keyword.update("
    assert updated =~ "String.replace(task,"
    assert updated =~ ~s(url: "http://localhost:8080")
    assert updated =~ "remote: false"
    assert updated =~ "# Keep this comment: café"
    assert updated =~ ~s(test: ["ecto.create", "test"])
    assert {:ok, _} = Code.string_to_quoted(updated)
  end

  test "replaces the previous evaluation-based alias" do
    source = """
    defmodule Demo.MixProject do
      use Mix.Project
      def project do
        [aliases: [compile: &Code.eval_string(File.read!("deps/tuist_ex/compile.exs"), args: &1)], tuist: [project: "account/demo", cache: true]]
      end
    end
    """

    config = [aliases: [compile: fn _ -> :ok end], tuist: [project: "account/demo", cache: true]]
    assert {:ok, updated} = ProjectSetup.configure(source, config)
    refute updated =~ "Code.eval_string"
    assert updated =~ "deps.compile tuist_ex --include-children"
  end

  test "leaves configured projects unchanged" do
    source = """
    defmodule Demo.MixProject do
      use Mix.Project
      def project, do: [app: :demo]
    end
    """

    config = [
      aliases: [compile: @bootstrap, test: "tuist.test"],
      tuist: [project: "account/demo", cache: true],
      test_coverage: [tool: TuistEx.Coverage]
    ]

    assert {:ok, ^source} = ProjectSetup.configure(source, config)
  end

  test "requires an explicit or already configured project" do
    assert {:error, message} = ProjectSetup.configure("invalid", [], project: "invalid")
    assert message =~ "--project account/project"
    assert {:error, _} = ProjectSetup.configure("invalid", [])
  end

  test "does not replace custom compile actions" do
    config = [aliases: [compile: ["custom", "tuist.compile"]]]

    assert {:error, message} =
             ProjectSetup.configure("def project, do: []", config, project: "a/b")

    assert message =~ "customized"
  end

  test "refuses dynamic return expressions without changing the source" do
    source = "defmodule Demo.MixProject do\ndef project, do: config()\nend\n"
    assert {:error, message} = ProjectSetup.configure(source, [], project: "a/b")
    assert message =~ "keyword list"
  end

  test "preserves Phoenix test preparation and test arguments" do
    source = """
    defmodule Demo.MixProject do
      use Mix.Project
      def project, do: [aliases: [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --trace"]]]
    end
    """

    config = [aliases: [test: ["ecto.create --quiet", "ecto.migrate --quiet", "test --trace"]]]
    assert {:ok, updated} = ProjectSetup.configure(source, config, project: "a/b")
    assert updated =~ ~s("ecto.create --quiet")
    assert updated =~ ~s("ecto.migrate --quiet")
    assert updated =~ ~s("tuist.test --trace")
    refute updated =~ ~s("test --trace")
    assert {:ok, _} = Code.string_to_quoted(updated)
  end

  test "refuses ambiguous or opaque custom test aliases without changing configuration" do
    for custom <- ["custom.test", ["test", "test"], ["ecto.setup"], fn _ -> :ok end] do
      assert {:error, message} =
               ProjectSetup.configure("def project, do: []", [aliases: [test: custom]],
                 project: "a/b"
               )

      assert message =~ "test alias is customized"
    end
  end

  test "keeps environment-dependent test preparation dynamic" do
    source = "def project, do: [aliases: selected_aliases()]"
    dev = [test: ["ecto.prepare_dev", "test"]]
    test = [test: ["ecto.prepare_test", "test --trace"]]
    assert {:ok, updated} = ProjectSetup.configure(source, [aliases: dev], project: "a/b")
    {:def, _, [_, [do: body]]} = Code.string_to_quoted!(updated)

    for {aliases, expected} <- [
          {dev, ["ecto.prepare_dev", "tuist.test"]},
          {test, ["ecto.prepare_test", "tuist.test --trace"]}
        ] do
      expression =
        Macro.prewalk(body, fn
          {:selected_aliases, _, []} -> Macro.escape(aliases)
          node -> node
        end)

      {config, _} = Code.eval_quoted(expression)
      assert config[:aliases][:test] == expected
    end
  end

  test "refuses syntax errors" do
    assert {:error, message} = ProjectSetup.configure("defmodule (", [], project: "a/b")
    assert message =~ "parse"
  end

  describe "coverage tool" do
    defp project(entries) do
      """
      defmodule Demo.MixProject do
        use Mix.Project
        def project do
          [app: :demo#{entries}]
        end
        defp test_coverage, do: [summary: false]
      end
      """
    end

    defp configure!(entries, config) do
      {:ok, updated} = ProjectSetup.configure(project(entries), config, project: "account/demo")
      {:ok, ast} = Code.string_to_quoted(updated)

      {_, [entries]} =
        Macro.prewalk(ast, [], fn
          {:def, _, [{:project, _, _}, [do: entries]]} = node, acc -> {node, [entries | acc]}
          node, acc -> {node, acc}
        end)

      {updated, entries[:test_coverage]}
    end

    test "sets TuistEx.Coverage as the project's tool" do
      assert {_, [tool: {:__aliases__, _, [:TuistEx, :Coverage]}]} = configure!("", [])
    end

    test "keeps the project's other coverage options" do
      {_, test_coverage} =
        configure!(", test_coverage: [summary: [threshold: 80]]",
          test_coverage: [summary: [threshold: 80]]
        )

      assert [tool: {:__aliases__, _, [:TuistEx, :Coverage]}, summary: [threshold: 80]] =
               test_coverage

      {updated, _} =
        configure!(", test_coverage: test_coverage()", test_coverage: [summary: false])

      assert updated =~ "test_coverage: Keyword.put_new(test_coverage(), :tool, TuistEx.Coverage)"
    end

    test "leaves a project that sets its own tool as it is" do
      {_, test_coverage} =
        configure!(", test_coverage: [tool: ExCoveralls]", test_coverage: [tool: ExCoveralls])

      assert [tool: {:__aliases__, _, [:ExCoveralls]}] = test_coverage
    end

    test "sets nothing at an umbrella's root, whose applications run their own tests" do
      assert {_, nil} = configure!(", apps_path: \"apps\"", apps_path: "apps")
    end
  end
end
