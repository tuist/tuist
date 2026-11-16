defmodule Tuist.Sandboxes.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.SandboxEvent

  @window_start ~U[2026-10-01 00:00:00Z]
  @window_end ~U[2026-10-03 00:00:00Z]

  # Each sandbox is `{vcpus, events}` or `{vcpus, events, source}`, and each
  # event `{event, at}` or `{event, at, boot}` with a boot's
  # `{boot_source, duration_ms}`.
  defp insert_events(account, sandbox_events) do
    sandbox_events
    |> Enum.flat_map(fn sandbox ->
      {vcpus, events, source} =
        case sandbox do
          {vcpus, events} -> {vcpus, events, "amp"}
          {vcpus, events, source} -> {vcpus, events, source}
        end

      sandbox_id = Ecto.UUID.generate()

      for event <- events do
        {name, at, {boot_source, duration_ms}} =
          case event do
            {name, at} -> {name, at, {"", 0}}
            {name, at, boot} -> {name, at, boot}
          end

        %{
          id: UUIDv7.generate(),
          account_id: account.id,
          sandbox_id: sandbox_id,
          event: name,
          source: source,
          vcpus: vcpus,
          memory_mb: vcpus * 2048,
          workspace_gb: 10,
          boot_source: boot_source,
          duration_ms: duration_ms,
          inserted_at: NaiveDateTime.from_iso8601!(at <> ".000000")
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

  test "counts created sandboxes per day against the previous window", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert result.dates == [~D[2026-10-01], ~D[2026-10-02], ~D[2026-10-03]]
    assert %{count: 2, trend: 100.0, values: [2, 0, 0]} = result.created
  end

  test "summarises setup and boot durations, leaving out starts that didn't boot", %{account: account} do
    insert_events(account, [
      {2,
       [
         {"started", "2026-10-01T09:00:30", {"template", 30_000}},
         {"setup", "2026-10-01T09:05:00", {"", 240_000}},
         {"paused", "2026-10-01T10:00:00"}
       ]},
      {2, [{"started", "2026-10-01T09:00:20", {"disk_snapshot", 20_000}}]},
      # A restore, then a resume of the running VM, which boots nothing.
      {2, [{"started", "2026-10-02T11:00:10", {"archive", 10_000}}, {"started", "2026-10-02T15:00:00"}]},
      {2, [{"setup", "2026-10-02T08:00:00", {"", 60_000}}]},
      {2,
       [
         {"started", "2026-09-30T10:01:00", {"template", 60_000}},
         {"setup", "2026-09-30T10:10:00", {"", 480_000}}
       ]}
    ])

    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{count: 2, avg: 150_000, p50: 60_000, p90: 240_000, trend_avg: -68.8} = result.setup
    assert result.setup.avg_values == [240_000, 60_000, nil]
    assert %{count: 3, avg: 20_000, p50: 20_000, p90: 30_000, trend_avg: -66.7} = result.time_to_start
    assert result.time_to_start.avg_values == [25_000, 10_000, nil]
  end

  test "counts events from the window's last second, where the date picker ends a window", %{account: account} do
    insert_events(account, [{2, [{"created", "2026-10-02T23:59:59"}]}])

    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: ~U[2026-10-02 23:59:59Z])

    assert %{count: 3, values: [2, 1]} = result.created
  end

  test "adds up vCPU-hours, running a sandbox that has not stopped until the window ends", %{account: account} do
    assert %{vcpu_hours: 13.0, values: [11.0, 2.0, +0.0]} =
             Analytics.compute(account.id, start_datetime: @window_start, end_datetime: @window_end)
  end

  test "measures the sessions that ended in the window", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{count: 3, avg: 4_200_000, p50: 3_600_000, p90: 7_200_000, p99: 7_200_000} = result.session_duration
    assert_in_delta result.session_duration.trend_avg, -41.7, 0.01

    assert result.session_duration.avg_values == [4_200_000, 0, 0]
  end

  test "reports the peak vCPUs and memory per day", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

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
    assert result.concurrency.vcpus == [0, 6, 4, 0]
  end
end
