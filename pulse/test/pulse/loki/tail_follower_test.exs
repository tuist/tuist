defmodule Pulse.Loki.TailFollowerTest do
  # Live tail across instances that share only object storage: this test's
  # runtime is the tailing instance, and `S3.append/3` stands in for another
  # instance's ingest, which never reaches this node's tailers directly.
  use Pulse.Test.Case, async: true

  alias Pulse.LogQL.NativeRange
  alias Pulse.LogQL.Parser
  alias Pulse.Loki.Tail
  alias Pulse.Loki.TailDelivery
  alias Pulse.Loki.TailFollower
  alias Pulse.Record.Log
  alias Pulse.Runtime
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  setup do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server = start_supervised!({Bandit, plug: {CompactionStore, agent: agent}, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "tail-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    Runtime.put_env(:pulse, Tail, poll_interval_ms: 20)
    # Restart the fixture's tail supervisor after its storage dependencies.
    # Reverse-order shutdown must stop periodic followers before removing the
    # manifest cache and HTTP store they poll, not just preserve configuration.
    :ok = stop_supervised(Tail)
    start_supervised!(ManifestSupervision)
    start_supervised!(Tail)
    {:ok, tenant: "tail-follow-#{System.unique_integer([:positive])}"}
  end

  defp record(line), do: %Log{timestamp_ns: System.os_time(:nanosecond), service: "api", body: line}

  defp lines(records), do: Enum.map(records, & &1.body)

  test "delivers records other instances publish, but not what existed before", ctx do
    assert :ok = S3.append(:logs, ctx.tenant, [record("before")])
    assert {:ok, follower} = Tail.join(ctx.tenant, 10)

    assert :ok = S3.append(:logs, ctx.tenant, [record("elsewhere 1")])
    assert lines(delivered()) == ["elsewhere 1"]

    assert :ok = S3.append(:logs, ctx.tenant, [record("elsewhere 2"), record("elsewhere 3")])
    assert Enum.sort(lines(delivered())) == ["elsewhere 2", "elsewhere 3"]

    # Several polls later nothing is delivered twice.
    for _ <- 1..3, do: send(follower, :poll)
    _ = :sys.get_state(follower)
    refute_received {Tail, _, _, _}
  end

  test "excess unseen storage backlog closes tails rather than returning a partial cursor", ctx do
    assert {:ok, [], cursor} = Storage.follow_logs(ctx.tenant, nil)
    for _ <- 1..65, do: assert(:ok = S3.append(:logs, ctx.tenant, [record("backlog")]))
    credit = TailDelivery.new()
    {:ok, _} = Registry.register(Tail.registry(), {:tailer, ctx.tenant}, credit)
    assert {:noreply, next} = TailFollower.handle_info(:poll, %{state(ctx.tenant) | cursor: cursor})
    assert next.cursor == nil
    assert_received :tail_overloaded
    refute_received {Tail, _, _, _}
  end

  test "this node's appends arrive once although storage also returns them", ctx do
    assert {:ok, follower} = Tail.join(ctx.tenant, 10)
    assert :ok = Storage.append(:logs, ctx.tenant, [record("local")])
    assert [%Log{body: "local"}] = delivered()

    for _ <- 1..3, do: send(follower, :poll)
    _ = :sys.get_state(follower)
    refute_received {Tail, _, _, _}
  end

  test "the follower stops once its tenant has no tailers, and tailers can restart it", ctx do
    assert {:ok, follower} = Tail.join(ctx.tenant, 10)
    ref = Process.monitor(follower)
    :ok = Tail.leave(ctx.tenant)
    assert_receive {:DOWN, ^ref, :process, ^follower, :normal}, 5_000

    assert {:ok, restarted} = Tail.follower(ctx.tenant)
    assert restarted != follower
  end

  test "identical entries are delivered once, as Loki deduplicates them" do
    entry = record("same")
    state = state("dedupe")
    {:ok, _} = Registry.register(Tail.registry(), {:tailer, "dedupe"}, TailDelivery.new())

    assert {:noreply, state} = TailFollower.handle_info({:published, [entry, entry]}, state)
    assert {:noreply, _state} = TailFollower.handle_info({:published, [entry, %{entry | body: "other"}]}, state)
    assert [%Log{body: "same"}] = delivered()
    assert [%Log{body: "other"}] = delivered()
    refute_received {Tail, _, _, _}
  end

  test "tail batches use native query regex semantics for Unicode labels and lines", ctx do
    records = for text <- ["é", "a", "☃"], do: %{record(text) | resource: %{"owner" => text}}
    assert :ok = S3.append(:logs, ctx.tenant, records)

    for {query, opts} <- [
          {~S'{service="api"} |~ "\\w+"', [line_filters: [{:match_re, "\\w+"}]]},
          {~S'{service="api",owner=~"\\w+"}', [matchers: [{"owner", :re, "\\w+"}]]},
          {~S'{service="api"} !~ "\\w+"', [line_filters: [{:not_match_re, "\\w+"}]]}
        ] do
      assert {:ok, ast} = Parser.parse(query)
      assert {:ok, expected} = S3.query(:logs, ctx.tenant, opts)
      actual = Tail.select(Tail.compile(ast), records)
      assert Enum.sort(Enum.map(actual, & &1.line)) == Enum.sort(lines(expected))
    end
  end

  test "Go regex classes, codepoint dots and strict ends agree across tail, raw and native metric scans", ctx do
    records = for text <- ["é", "٣", "a foo b", "a\n", "\v"], do: record(text)
    assert :ok = S3.append(:logs, ctx.tenant, records)
    Process.put(:promql_budget, %{})
    Process.put(:promql_deadline_ms, System.monotonic_time(:millisecond) + 30_000)

    for {pattern, expected} <- [
          {"^.$", ["é", "٣", "\v"]},
          {"^\\d$", []},
          {"\\bfoo\\b", ["a foo b"]},
          {"^\\s$", []},
          {"^[\\S]$", ["é", "٣", "\v"]},
          {"^\\v$", ["\v"]}
        ] do
      query = ~s'{service="api"} |~ ' <> Pulse.JSON.encode!(pattern)
      assert {:ok, ast} = Parser.parse(query)
      assert Enum.sort(Enum.map(Tail.select(Tail.compile(ast), records), & &1.line)) == Enum.sort(expected)
      opts = [line_filters: [{:match_re, pattern}]]
      assert {:ok, raw} = S3.query(:logs, ctx.tenant, opts)
      assert Enum.sort(lines(raw)) == Enum.sort(expected)
      assert Enum.sort(lines(Memory.select_logs(records, opts))) == Enum.sort(expected)
      window = %{start_ts_ns: 0, end_ts_ns: System.os_time(:nanosecond)}
      assert {:ok, packed} = NativeRange.collect(ast, %{op: :count_over_time, grouping: nil}, ctx.tenant, window)

      assert Enum.sum(Enum.map(packed, fn {_labels, {:packed, bytes}} -> div(byte_size(bytes), 17) end)) ==
               length(expected)
    end
  end

  test "tail supervisor downtime does not fail an already durable log append" do
    assert :ok = stop_supervised(Tail)
    entry = record("acknowledged without live tail")
    assert :ok = Storage.append(:logs, "tail-unavailable", [entry])
    assert {:ok, [^entry]} = Storage.query(:logs, "tail-unavailable")
  end

  test "distinct lines with the same 32-bit hash are not dropped" do
    first = %{record("adversarial-tail-137642") | timestamp_ns: 123}
    second = %{first | body: "adversarial-tail-171648"}
    assert :erlang.phash2(first.body, 4_294_967_296) == :erlang.phash2(second.body, 4_294_967_296)
    {:ok, _} = Registry.register(Tail.registry(), {:tailer, "collision"}, TailDelivery.new())

    assert {:noreply, state} = TailFollower.handle_info({:published, [first, second, first]}, state("collision"))
    assert [^first, ^second] = delivered()
    assert map_size(state.delivered) == 2
    refute_received {Tail, _, _, _}
  end

  test "identity payload bytes remain bounded within a single large batch" do
    records = for i <- 1..2_100, do: %{record(String.duplicate("x", 8192)) | timestamp_ns: i}
    assert {:noreply, state} = TailFollower.handle_info({:published, records}, state("bytes"))
    assert state.identity_bytes <= 16 * 1024 * 1024
    assert map_size(state.delivered) < length(records)
    assert :queue.len(state.order) == map_size(state.delivered)

    assert state.identity_bytes ==
             Enum.sum(Enum.map(:queue.to_list(state.order), fn {_at, _key, bytes} -> bytes end))

    # The retained suffix still deduplicates; eviction does not discard delivery.
    {:ok, _} = Registry.register(Tail.registry(), {:tailer, "bytes"}, TailDelivery.new())
    assert {:noreply, _state} = TailFollower.handle_info({:published, [List.last(records)]}, state)
    refute_received {Tail, _, _, _}
  end

  test "retained identity strings do not pin larger request or column arenas" do
    arena = String.duplicate("x", 1024 * 1024)
    line = binary_part(arena, 100, 1024)
    service = binary_part(arena, 2000, 128)
    assert :binary.referenced_byte_size(line) > byte_size(line)

    assert {:noreply, state} =
             TailFollower.handle_info({:published, [%{record(line) | service: service}]}, state("arenas"))

    [{_timestamp, labels, retained_line}] = Map.keys(state.delivered)
    assert retained_line == line
    assert :binary.referenced_byte_size(retained_line) == byte_size(line)

    for {name, value} <- labels do
      assert :binary.referenced_byte_size(name) == byte_size(name)
      assert :binary.referenced_byte_size(value) == byte_size(value)
    end
  end

  defp delivered do
    assert_receive {Tail, credit, bytes, records}, 5_000
    TailDelivery.release(credit, bytes)
    records
  end

  defp state(tenant) do
    %{tenant: tenant, interval: 1_000, cursor: nil, idle: 0, delivered: %{}, identity_bytes: 0, order: :queue.new()}
  end
end
