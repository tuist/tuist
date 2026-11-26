defmodule Tuist.RemoteExecution.TaskSizesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.FeatureFlags
  alias Tuist.RemoteExecution
  alias Tuist.RemoteExecution.TaskSizes
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @gib 1024 * 1024 * 1024

  setup do
    stub(FeatureFlags, :remote_execution_task_sizing_enabled?, fn _ -> true end)
    %{project: project(16, 32)}
  end

  defp project(vcpus, memory_gb) do
    project = ProjectsFixtures.project_fixture(build_system: :bazel)

    {:ok, account} =
      RemoteExecution.update_limits(Repo.reload!(project.account), %{
        remote_execution_vcpus_limit: vcpus,
        remote_execution_memory_gb_limit: memory_gb
      })

    %{project | account: account}
  end

  defp key(n), do: n |> Integer.to_string() |> String.pad_leading(64, "0")

  defp run(project, key, usage) do
    usage =
      Map.merge(%{"cpu_ms" => 1000, "wall_ms" => 10_000, "p90_cores" => 1.0, "anon_peak_bytes" => 0, "vcpus" => 8}, usage)

    :ok = TaskSizes.record(project, [%{"size_key" => key, "memory_gb" => 4, "target" => "//pkg:t", "usage" => usage}])
  end

  defp choose(project, key, asked \\ 4, params \\ %{}),
    do: TaskSizes.choose(project, asked, Map.put(params, "size_key", key))

  test "a measured peak picks the smallest VM whose usable memory holds it with margin", %{project: project} do
    # 5 GiB × 1.3 is more than a 4 GiB VM holds and less than an 8 GiB one's usable memory.
    run(project, key(1), %{"anon_peak_bytes" => 5 * @gib})
    # 5.7 GiB × 1.3 is more than 8 GiB less the guest's overhead.
    run(project, key(2), %{"anon_peak_bytes" => round(5.7 * @gib)})

    assert {8, _} = choose(project, key(1))
    assert {16, _} = choose(project, key(2))
    # Unmeasured actions run at the size they ask for, with the VM's own weight.
    assert {4, nil} = choose(project, key(3))
  end

  test "a low run decays a high peak by a fifth instead of replacing it", %{project: project} do
    run(project, key(1), %{"anon_peak_bytes" => 6 * @gib})
    run(project, key(1), %{"anon_peak_bytes" => @gib})

    # 0.8 × 6 GiB still needs an 8 GiB VM; the last run alone would fit 4 GiB.
    assert {8, _} = choose(project, key(1))
  end

  test "an OOM kill runs the next runs one size up even when the peak read low", %{project: project} do
    run(project, key(1), %{"anon_peak_bytes" => @gib, "oom_kills" => 1})
    assert {8, _} = choose(project, key(1))
  end

  test "an explicit size is a floor, and task sizing off keeps exactly it", %{project: project} do
    run(project, key(1), %{"anon_peak_bytes" => @gib, "cpu_ms" => 40_000})

    assert {16, _} = choose(project, key(1), 16)
    run(project, key(2), %{"anon_peak_bytes" => 6 * @gib})
    assert {2, nil} = choose(project, key(2), 2, %{"task_sizing" => false})
  end

  test "an action without a size starts at 2 GB, and its measurements take it below 4 GB", %{project: project} do
    implicit = %{"memory_explicit" => false}
    # 1.2 GiB × 1.3 needs more than a 2 GiB VM's usable memory.
    run(project, key(1), %{"anon_peak_bytes" => round(1.2 * @gib)})
    run(project, key(2), %{"anon_peak_bytes" => div(@gib, 2)})

    assert {4, _} = choose(project, key(1), 4, implicit)
    assert {2, _} = choose(project, key(2), 4, implicit)
    assert {2, nil} = choose(project, key(3), 4, implicit)
    assert {2, nil} = choose(project, key(2), 4, Map.put(implicit, "task_sizing", false))
    # Asked for, or from a gateway that does not mark it, 4 GB stays a floor.
    assert {4, _} = choose(project, key(2), 4)

    stub(FeatureFlags, :remote_execution_task_sizing_enabled?, fn _ -> false end)
    assert {4, nil} = choose(project, key(2), 4, implicit)
  end

  test "a measured size the account's limits do not hold is lowered to the largest that fits" do
    project = project(16, 8)
    run(project, key(1), %{"anon_peak_bytes" => 10 * @gib})
    assert {8, _} = choose(project, key(1))
  end

  test "the guarantee is the cores used, rounded up to half a vCPU and capped at half the account's vCPUs",
       %{project: project} do
    run(project, key(1), %{"cpu_ms" => 32_000, "wall_ms" => 10_000})
    run(project, key(2), %{"cpu_ms" => 100, "wall_ms" => 10_000})
    run(project, key(3), %{"cpu_ms" => 80_000, "wall_ms" => 10_000})

    assert {_, 3500} = choose(project, key(1))
    assert {_, 500} = choose(project, key(2))
    # 8 cores, capped at half of 16.
    assert {_, 8000} = choose(project, key(3))

    small = project(4, 32)
    run(small, key(1), %{"cpu_ms" => 32_000, "wall_ms" => 10_000})
    assert {_, 2000} = choose(small, key(1))
  end

  test "without the flag nothing changes, though measurements are kept", %{project: project} do
    stub(FeatureFlags, :remote_execution_task_sizing_enabled?, fn _ -> false end)
    run(project, key(1), %{"anon_peak_bytes" => 6 * @gib, "cpu_ms" => 40_000})

    assert {4, nil} = choose(project, key(1))
    assert [] = TaskSizes.sized_keys(project)
    assert Repo.get_by(Tuist.RemoteExecution.TaskSize, project_id: project.id, key: key(1))
  end

  test "sized keys are those a leased 2 GB VM would not hold", %{project: project} do
    run(project, key(1), %{"anon_peak_bytes" => round(1.2 * @gib)})
    # More than the 1 vCPU a 2 GB VM guarantees.
    run(project, key(2), %{"cpu_ms" => 15_000, "wall_ms" => 10_000})
    run(project, key(3), %{"anon_peak_bytes" => div(@gib, 2), "cpu_ms" => 8_000, "wall_ms" => 10_000})

    assert Enum.sort(TaskSizes.sized_keys(project)) == [key(1), key(2)]
  end
end
