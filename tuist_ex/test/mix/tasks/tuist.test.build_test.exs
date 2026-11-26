defmodule Mix.Tasks.Tuist.Test.BuildTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  # The task configures the project's analytics and installs Mimic globally,
  # so it runs in its own VM, as `mix tuist.test`'s selection test does.
  test "hands the shards the impact run of a selection and of a fallback", %{tmp_dir: tmp_dir} do
    script = ~S"""
    Mix.start()
    Mix.env(:test)

    config = [
      tuist: [selective_testing: [strategy: :coverage]],
      test_coverage: [tool: :custom]
    ]

    Mix.Project.in_project(:tuist_ex, File.cwd!(), config, fn _ ->
      {:ok, _} = Application.ensure_all_started(:mimic)
      Code.require_file("test/test_helper.exs")
      Mimic.copy(TuistEx.Analytics.TestSelection)
      Mimic.copy(TuistEx.Analytics.Shards)
      Mimic.copy(TuistEx.Analytics.Coverage)
      ExUnit.configure(autorun: false)

      defmodule BuildSelectionRegression do
        use ExUnit.Case, async: false

        test "the plan carries the impact run" do
          Mimic.set_mimic_global()
          owner = self()
          Mimic.stub(TuistEx.Analytics.Shards, :reference, fn _options -> {:ok, "ref"} end)
          Mimic.stub(TuistEx.Analytics.Coverage, :instrument, fn _paths -> {0, []} end)

          Mimic.stub(TuistEx.Analytics.Shards, :create_plan, fn _reference, modules, _concurrent, options ->
            send(owner, {:plan, modules, options[:test_impact_run_id]})
            {:ok, %{"shards" => []}}
          end)

          plan = fn outcome ->
            Mimic.stub(TuistEx.Analytics.TestSelection, :decide, fn _index, _options -> outcome end)

            ExUnit.CaptureIO.capture_io(fn ->
              Mix.Tasks.Tuist.Test.Build.run(["--cover", "--no-upload"])
            end)

            assert_received {:plan, modules, run_id}
            {modules, run_id}
          end

          {all, "run-1"} =
            plan.({:selected, %{run_id: "run-1", counts: %{}, skipped_tests: []}})

          # The shards run everything and report the run, which is how the
          # test runs show why nothing was skipped.
          assert plan.({:fallback, %{run_id: "run-2", reason: "no_baseline", matched_path: nil}}) ==
                   {all, "run-2"}

          assert plan.({:failed, :timeout}) == {all, nil}
          IO.puts("build selection verified")
        end
      end

      if ExUnit.run().failures != 0, do: System.halt(1)
    end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [{"GITHUB_OUTPUT", Path.join(tmp_dir, "github_output")}, {"TUIST_SHARD_INDEX", ""}]
      )

    assert status == 0, output
    assert output =~ "build selection verified"
  end
end
