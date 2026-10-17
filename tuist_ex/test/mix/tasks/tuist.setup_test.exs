defmodule Mix.Tasks.Tuist.SetupTest do
  use ExUnit.Case, async: true

  test "sets up a project once and preserves its file permissions" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "tuist-setup-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    file = Path.join(directory, "mix.exs")

    File.write!(file, """
    defmodule SetupFixture.MixProject do
      use Mix.Project
      def project do
        # Project settings stay here.
        [app: :setup_fixture, version: "0.1.0", aliases: [test: "test"]]
      end
    end
    """)

    File.chmod!(file, 0o640)
    ebin = :tuist_ex |> :code.lib_dir() |> to_string() |> Path.join("ebin")

    script = """
    Mix.start()
    Mix.Project.in_project(:setup_fixture, File.cwd!(), fn _ ->
      Mix.Tasks.Tuist.Setup.run(["--project", "account/project"])
    end)
    """

    run = fn ->
      System.cmd(System.find_executable("elixir"), ["-pa", ebin, "-e", script],
        cd: directory,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}]
      )
    end

    {output, status} = run.()
    assert status == 0, output
    assert output =~ "Updated mix.exs"
    updated = File.read!(file)
    assert updated =~ "cache: true"
    assert updated =~ "# Project settings stay here."
    assert updated =~ ~s(test: "tuist.test")
    assert updated =~ "test_coverage: [tool: TuistEx.Coverage]"
    refute updated =~ "Code.eval"
    assert Bitwise.band(File.stat!(file).mode, 0o777) == 0o640
    {output, status} = run.()
    assert status == 0, output
    assert output =~ "already configured"
    assert File.read!(file) == updated
    assert File.ls!(directory) |> Enum.all?(&(not String.contains?(&1, ".tuist-")))
  end

  test "rejects unknown arguments without accessing the current project" do
    assert_raise Mix.Error, ~r/Usage: mix tuist.setup/, fn ->
      Mix.Tasks.Tuist.Setup.run(["--unknown"])
    end
  end
end
