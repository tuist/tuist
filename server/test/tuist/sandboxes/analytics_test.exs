defmodule Tuist.Sandboxes.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.SandboxEvent
  alias Tuist.Sandboxes.UsageEvent

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
          guaranteed_cpu_milli: 0,
          error_message: "",
          node_name: "",
          template: "",
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

  test "adds up vCPU-hours and memory, running a sandbox that has not stopped until the window ends", %{
    account: account
  } do
    # Each sandbox has 2 GiB per vCPU.
    assert %{vcpu_hours: 13.0, values: [11.0, 2.0, +0.0], memory_gib_hours: 26.0, memory_values: [22.0, 4.0, +0.0]} =
             Analytics.compute(account.id, start_datetime: @window_start, end_datetime: @window_end)
  end

  test "bills bursting sandboxes their metered CPU, and older sessions their vCPUs until metering starts", %{
    account: account
  } do
    legacy = Ecto.UUID.generate()
    bursting = Ecto.UUID.generate()

    event = fn sandbox_id, name, at, vcpus, guaranteed ->
      %{
        id: UUIDv7.generate(),
        account_id: account.id,
        sandbox_id: sandbox_id,
        event: name,
        source: "amp",
        vcpus: vcpus,
        memory_mb: 8192,
        workspace_gb: 10,
        boot_source: "",
        duration_ms: 0,
        guaranteed_cpu_milli: guaranteed,
        error_message: "",
        node_name: "",
        template: "",
        inserted_at: NaiveDateTime.from_iso8601!(at <> ".000000")
      }
    end

    SandboxEvent.Buffer.insert_all([
      # Started before metering, which took over two hours later.
      event.(legacy, "started", "2026-10-01T10:00:00", 4, 0),
      # Its 16 vCPUs never count, only what it was metered.
      event.(bursting, "started", "2026-10-01T15:00:00", 16, 250),
      event.(bursting, "paused", "2026-10-01T17:00:00", 16, 250)
    ])

    usage = fn sandbox_id, at, billed_ms ->
      %{
        id: UUIDv7.generate(),
        account_id: account.id,
        sandbox_id: sandbox_id,
        source: "amp",
        vcpus: 16,
        memory_mb: 8192,
        guaranteed_cpu_milli: 250,
        duration_ms: 30_000,
        used_cpu_ms: billed_ms,
        billed_cpu_ms: billed_ms,
        used_memory_bytes: 0,
        excess_memory_mib_ms: 0,
        inserted_at: NaiveDateTime.from_iso8601!(at <> ".000000")
      }
    end

    UsageEvent.Buffer.insert_all([
      usage.(legacy, "2026-10-01T12:00:00", 3_600_000),
      usage.(legacy, "2026-10-02T01:00:00", 1_800_000),
      # It also held 4 GiB past its request for an hour.
      %{usage.(bursting, "2026-10-01T15:30:00", 1_440_000) | excess_memory_mib_ms: 4096 * 3_600_000},
      # Another account's usage is not this one's.
      %{usage.(bursting, "2026-10-01T15:30:00", 3_600_000) | account_id: account.id + 1}
    ])

    # The setup's 11 and 2 vCPU-hours, the legacy session's 4 vCPUs from
    # 10:00 to 12:00, and 1 + 0.4 and 0.5 metered CPU-hours.
    # Memory is reserved whether a sandbox bursts or not: the setup's 26
    # GiB-hours, the legacy sandbox's 8 GiB for its 38 hours, and the
    # bursting one's 8 GiB for 2 plus the 4 GiB-hours it held past them.
    assert %{
             vcpu_hours: 22.9,
             values: [20.4, 2.5, +0.0],
             memory_gib_hours: 350.0,
             memory_values: [154.0, 196.0, +0.0]
           } =
             Analytics.compute(account.id, start_datetime: @window_start, end_datetime: @window_end)

    assert %{vcpus: [peak_day_one | _]} =
             Analytics.overview(account.id, start_datetime: @window_start, end_datetime: @window_end).concurrency

    # The setup's 6 vCPUs and the legacy sandbox's 4 overlap at 10:30; the
    # bursting one adds its quarter core, not its 16 vCPUs.
    assert peak_day_one == 10
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
