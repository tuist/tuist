defmodule TuistEx.Analytics.MutedFailuresTest do
  use ExUnit.Case, async: true

  # ExUnit runs one suite per VM, and the patch swaps a module of ExUnit's
  # own, so the suites run in a VM of their own.
  defp run_script(script) do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end

  test "leaves only the muted test's failure out of the run's failure count" do
    output =
      run_script(~S"""
      alias TuistEx.Analytics.MutedFailures
      alias TuistEx.Analytics.Quarantine

      manifest = Path.join(System.tmp_dir!(), "tuist-ex-muted-#{System.unique_integer([:positive])}")
      policy = %Quarantine{muted: MapSet.new([{"CartTest", "add/2", "flakes"}])}

      :ok = MutedFailures.install(policy)
      :ok = MutedFailures.install(policy)
      true = MutedFailures.installed?()
      ExUnit.start(autorun: false, formatters: [], failures_manifest_path: manifest)

      # The same test in another module is not muted, and neither is a
      # muted test's describe block's other test. The failures manifest
      # keeps only tests whose file exists.
      file = manifest <> "_test.exs"

      File.write!(file, ~S|
      for module <- [CartTest, OrderTest] do
        defmodule module do
          use ExUnit.Case

          describe "add/2" do
            test "flakes", do: assert(false)
            test "passes", do: :ok
          end
        end
      end
      |)

      Code.require_file(file)

      %{total: 4, failures: 1} = ExUnit.run()

      # `--failed` still reruns it.
      failed = ExUnit.FailuresManifest.read(manifest)
      true = Map.has_key?(failed, {CartTest, :"test add/2 flakes"})
      true = Map.has_key?(failed, {OrderTest, :"test add/2 flakes"})
      File.rm!(manifest)
      File.rm!(file)

      :ok = MutedFailures.uninstall()
      false = MutedFailures.installed?()
      ExUnit.RunnerStats = ExUnit.RunnerStats.__info__(:module)
      IO.puts("muted failure count verified")
      """)

    assert output =~ "muted failure count verified"
  end

  test "counts every failure without muted tests" do
    output =
      run_script(~S"""
      alias TuistEx.Analytics.MutedFailures

      :ok = MutedFailures.install(%TuistEx.Analytics.Quarantine{})
      ExUnit.start(autorun: false, formatters: [])

      defmodule SetupFailsTest do
        use ExUnit.Case
        setup_all do: raise("boom")
        test "never runs", do: :ok
      end

      %{total: 1, failures: 1} = ExUnit.run()
      IO.puts("unmuted failure count verified")
      """)

    assert output =~ "unmuted failure count verified"
  end
end
