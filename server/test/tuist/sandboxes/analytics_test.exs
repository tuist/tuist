defmodule Tuist.Sandboxes.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.SandboxEvent

  @window_start ~U[2026-10-01 00:00:00Z]
  @window_end ~U[2026-10-03 00:00:00Z]

  defp insert_events(account, sandbox_events) do
    sandbox_events
    |> Enum.flat_map(fn {vcpus, events} ->
      sandbox_id = Ecto.UUID.generate()

      for {event, at} <- events do
        %{
          id: UUIDv7.generate(),
          account_id: account.id,
          sandbox_id: sandbox_id,
          event: event,
          source: "amp",
          vcpus: vcpus,
          memory_mb: vcpus * 2048,
          inserted_at: NaiveDateTime.from_iso8601!(at)
        }
      end
    end)
    |> SandboxEvent.Buffer.insert_all()
  end

  setup do
    account = account_fixture()

    insert_events(account, [
      {2,
       [
         {"created", "2026-10-01T10:00:00"},
         {"started", "2026-10-01T10:00:00"},
         {"paused", "2026-10-01T11:00:00"},
         {"started", "2026-10-01T14:00:00"},
         {"failed", "2026-10-01T14:30:00"}
       ]},
      {4,
       [
         {"created", "2026-10-01T10:30:00"},
         {"started", "2026-10-01T10:30:00"},
         {"paused", "2026-10-01T12:30:00"},
         {"deleted", "2026-10-01T18:00:00"}
       ]},
      {2,
       [
         {"created", "2026-09-30T10:00:00"},
         {"started", "2026-09-30T10:00:00"},
         {"paused", "2026-09-30T12:00:00"}
       ]},
      {2, [{"started", "2026-10-02T23:00:00"}]}
    ])

    %{account: account}
  end

  test "counts created and failed sandboxes per day against the previous window", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert result.dates == [~D[2026-10-01], ~D[2026-10-02], ~D[2026-10-03]]
    assert %{count: 2, trend: 100.0, values: [2, 0, 0]} = result.created
    assert %{count: 1, trend: 0.0, values: [1, 0, 0]} = result.failed
  end

  test "adds up vCPU-hours, running a sandbox that has not stopped until the window ends", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{vcpu_hours: 13.0, trend: 225.0, values: [11.0, 2.0, 0.0]} = result.compute
  end

  test "measures the sessions that ended in the window", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{count: 3, avg: 4_200_000, p50: 3_600_000, p90: 7_200_000, p99: 7_200_000} = result.session_duration
    assert_in_delta result.session_duration.trend_avg, -41.7, 0.01

    assert result.session_duration.avg_values == [4_200_000, 0, 0]
  end

  test "reports the peak running sandboxes, vCPUs and memory per day", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert result.concurrency.sandboxes == [2, 1, 0]
    assert result.concurrency.vcpus == [6, 2, 0]
    assert result.concurrency.memory_gb == [12.0, 4.0, 0.0]
  end

  test "buckets a short window by hour, leaving a session out of the hour it ended at", %{account: account} do
    result =
      Analytics.overview(account.id,
        start_datetime: ~U[2026-10-01 09:00:00Z],
        end_datetime: ~U[2026-10-01 12:00:00Z]
      )

    assert length(result.dates) == 4
    assert result.concurrency.sandboxes == [0, 2, 1, 0]
    assert result.compute.values == [0.0, 4.0, 4.0, 0.0]
  end
end
