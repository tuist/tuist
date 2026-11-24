defmodule Tuist.RemoteExecution.UsageTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.IngestRepo
  alias Tuist.RemoteExecution.Usage
  alias Tuist.RemoteExecution.UsageEvent
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "project usage counts the project's executions in the half-open period by shape, mode and day" do
    project = ProjectsFixtures.project_fixture()
    other_project = ProjectsFixtures.project_fixture(account: project.account)

    event = fn project, inserted_at, vcpus, mode, duration_ms ->
      %{
        id: UUIDv7.generate(),
        account_id: project.account_id,
        project_id: project.id,
        sandbox_id: UUIDv7.generate(),
        mode: mode,
        vcpus: vcpus,
        memory_mb: vcpus * 2048,
        duration_ms: duration_ms,
        inserted_at: inserted_at
      }
    end

    IngestRepo.insert_all(UsageEvent, [
      event.(project, ~N[2026-07-14 10:00:00.000000], 2, "scheduled", 1_000),
      event.(project, ~N[2026-07-14 11:00:00.000000], 8, "scheduled", 60_000),
      event.(project, ~N[2026-07-16 23:59:59.500000], 2, "leased", 3_000),
      # Outside the period on either side, and another project of the account.
      event.(project, ~N[2026-07-13 23:59:59.999999], 2, "scheduled", 5_000),
      event.(project, ~N[2026-07-17 00:00:00.000000], 2, "scheduled", 7_000),
      event.(other_project, ~N[2026-07-15 12:00:00.000000], 2, "scheduled", 11_000)
    ])

    usage = Usage.project_usage(project, ~U[2026-07-14 00:00:00Z], ~U[2026-07-17 00:00:00Z])

    assert %{executions: 3, execution_ms: 64_000, granularity: :day} = usage
    assert usage.dates == ["2026-07-14", "2026-07-15", "2026-07-16"]

    assert usage.series == [
             %{executions: 2, execution_ms: 61_000},
             %{executions: 0, execution_ms: 0},
             %{executions: 1, execution_ms: 3_000}
           ]

    assert [
             %{vcpus: 2, memory_gb: 4, executions: 2, execution_ms: 4_000} = small,
             %{vcpus: 8, memory_gb: 16, executions: 1, execution_ms: 60_000}
           ] = usage.shapes

    assert Enum.map(small.series, & &1.execution_ms) == [1_000, 0, 3_000]

    assert usage.modes == [
             %{mode: "leased", executions: 1, execution_ms: 3_000},
             %{mode: "scheduled", executions: 2, execution_ms: 61_000}
           ]
  end
end
