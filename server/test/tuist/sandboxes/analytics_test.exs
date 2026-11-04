defmodule Tuist.Sandboxes.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

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

  test "times boots until ready, waiting for an Orb's setup and leaving out one that hasn't shown it", %{
    account: account
  } do
    insert_events(account, [
      # A cold Orb: a 30 s boot, then setup until 09:05, ready 5 min after
      # the boot began. A later rerun of setup doesn't count.
      {2,
       [
         {"started", "2026-10-01T09:00:30", {"template", 30_000}},
         {"setup", "2026-10-01T09:05:00"},
         {"paused", "2026-10-01T10:00:00"},
         {"setup", "2026-10-01T12:00:00"}
       ]},
      # From a project snapshot, ready once booted.
      {2, [{"started", "2026-10-01T09:00:20", {"disk_snapshot", 20_000}}]},
      # A cold Orb that paused with no setup: it had none to run.
      {2, [{"started", "2026-10-02T08:01:00", {"template", 60_000}}, {"paused", "2026-10-02T09:00:00"}]},
      # A cold Orb still running with no setup yet: not known, left out.
      {2, [{"started", "2026-10-02T10:00:40", {"template", 40_000}}]},
      # An API sandbox has no setup to wait for.
      {2, [{"started", "2026-10-02T11:00:10", {"template", 10_000}}], "api"},
      # A restore in the previous window.
      {2, [{"started", "2026-09-30T10:01:00", {"archive", 60_000}}]}
    ])

    %{time_to_ready: ready} = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{count: 4, avg: 97_500, p50: 20_000, p90: 300_000, p99: 300_000, trend_avg: 62.5} = ready
    assert ready.avg_values == [160_000, 35_000, 0]
    assert ready.by_source["template"].p50_values == [300_000, 10_000, nil]
    assert ready.by_source["disk_snapshot"].p50_values == [20_000, nil, nil]
    assert ready.by_source["archive"].count == 0
  end

  test "counts events from the window's last second, where the date picker ends a window", %{account: account} do
    insert_events(account, [{2, [{"created", "2026-10-02T23:59:59"}]}])

    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: ~U[2026-10-02 23:59:59Z])

    assert %{count: 3, values: [2, 1]} = result.created
  end

  test "adds up vCPU-hours, running a sandbox that has not stopped until the window ends", %{account: account} do
    result = Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{vcpu_hours: 13.0, trend: 225.0, values: [11.0, 2.0, +0.0]} = result.compute
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
