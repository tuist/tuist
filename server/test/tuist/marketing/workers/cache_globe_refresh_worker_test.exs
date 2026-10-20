defmodule Tuist.Marketing.Workers.CacheGlobeRefreshWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Marketing.CacheGlobe
  alias Tuist.Marketing.Workers.CacheGlobeRefreshWorker

  @key "marketing-cache_globe-playback-v1"
  @origin %{
    location: [65.0, -19.0],
    region: "eu-west",
    window_start: "2035-01-10T11:58:00Z",
    window_seconds: 60,
    playback_delay_seconds: 300,
    downloads: 9.0
  }

  setup :verify_on_exit!

  test "without shared Redis, writes measured counters but never releases per-replica country cells" do
    snapshot = snapshot()
    stub(Environment, :redis_url, fn -> nil end)
    expect(CacheGlobe, :snapshot, fn -> snapshot end)
    reject(Redix, :command, 3)
    expect_snapshot(snapshot, [])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "unpublished yesterday candidates cannot fabricate replay status without Redis or measurements today" do
    origin = %{@origin | window_start: "2035-01-09T23:59:00Z"}

    snapshot =
      snapshot(%{downloads: 0, origins: [origin], observed_at: nil, status: :waiting, updated_at: "2035-01-10T00:02:00Z"})

    stub(Environment, :redis_url, fn -> nil end)
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect(KeyValueStore, :put, fn [:marketing, :cache_globe], published, _opts ->
      assert published.downloads == 0
      assert published.origins == []
      assert published.status == :waiting
      assert published.observed_at == nil
      {:ok, true}
    end)

    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "freezes an already released cell before publishing and retains it through late reports" do
    shared_redis()
    snapshot = snapshot(%{origins: [%{@origin | downloads: 12.0}]})
    previous = %{version: 1, since: "2035-01-10T11:50:00Z", origins: [@origin]}
    expect(CacheGlobe, :snapshot, fn -> snapshot end)
    expect_journal(previous, fn state -> assert state.origins == [@origin] end)
    expect_snapshot(snapshot, [@origin])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "a missing journal establishes a watermark rather than re-releasing older cells" do
    shared_redis()
    snapshot = snapshot()
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect_journal(nil, fn state ->
      assert state.since == snapshot.updated_at
      assert state.origins == []
    end)

    expect_snapshot(snapshot, [])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "a journal read failure disables arcs but still publishes measured totals" do
    shared_redis()
    snapshot = snapshot()
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect(Redix, :command, fn :test_redis, ["GET", @key], opts ->
      assert opts[:timeout] == 5000
      {:error, %Redix.Error{message: "Unavailable"}}
    end)

    expect_snapshot(snapshot, [])

    assert capture_log(fn ->
             assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
           end) =~ "playback journal unavailable"
  end

  test "a missing Redis process cannot prevent measured counters from updating" do
    shared_redis()
    snapshot = snapshot()
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect(Redix, :command, fn :test_redis, ["GET", @key], _opts ->
      exit({:noproc, {GenServer, :call, [:test_redis, :get]}})
    end)

    expect_snapshot(snapshot, [])

    assert capture_log(fn ->
             assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
           end) =~ "playback journal unavailable"
  end

  test "a failed journal write never publishes unfrozen cells" do
    shared_redis()
    snapshot = snapshot()
    previous = %{version: 1, since: "2035-01-10T11:50:00Z", origins: []}
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect(Redix, :command, 2, fn :test_redis, command, _opts ->
      case command do
        ["GET", @key] -> {:ok, :erlang.term_to_binary(previous)}
        ["SET", @key, _encoded, "EX", 1200] -> {:error, %Redix.Error{message: "Unavailable"}}
      end
    end)

    expect_snapshot(snapshot, [])

    assert capture_log(fn ->
             assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
           end) =~ "playback journal unavailable"
  end

  test "a corrupt journal resets safely and cannot re-release a previous window" do
    shared_redis()
    snapshot = snapshot()
    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect(Redix, :command, 2, fn :test_redis, command, _opts ->
      case command do
        ["GET", @key] ->
          {:ok, "not an Erlang term"}

        ["SET", @key, encoded, "EX", 1200] ->
          state = :erlang.binary_to_term(encoded, [:safe])
          assert state.since == snapshot.updated_at
          assert state.origins == []
          {:ok, "OK"}
      end
    end)

    expect_snapshot(snapshot, [])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "malformed journal entries reset safely and do not prevent counter updates" do
    shared_redis()
    snapshot = snapshot()
    previous = %{version: 1, since: "2035-01-10T11:50:00Z", origins: [%{@origin | window_start: "invalid"}]}
    expect(CacheGlobe, :snapshot, fn -> snapshot end)
    expect_journal(previous, fn state -> assert state.origins == [] end)
    expect_snapshot(snapshot, [])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "journal metadata and entries are whitelisted before publishing" do
    shared_redis()
    snapshot = snapshot()

    previous = %{
      version: 1,
      since: "2035-01-10T11:50:00Z",
      origins: [Map.put(@origin, :account_id, 123)],
      account_id: 123
    }

    expect(CacheGlobe, :snapshot, fn -> snapshot end)

    expect_journal(previous, fn state ->
      refute Map.has_key?(state, :account_id)
      refute Map.has_key?(hd(state.origins), :account_id)
    end)

    expect_snapshot(snapshot, [@origin])
    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  test "retained yesterday windows keep replay available without changing today's zero totals" do
    shared_redis()
    origin = %{@origin | window_start: "2035-01-09T23:59:00Z"}

    snapshot =
      snapshot(%{downloads: 0, origins: [], observed_at: nil, status: :waiting, updated_at: "2035-01-10T00:04:00Z"})

    previous = %{version: 1, since: "2035-01-09T23:00:00Z", origins: [origin]}
    expect(CacheGlobe, :snapshot, fn -> snapshot end)
    expect_journal(previous, fn state -> assert state.origins == [origin] end)

    expect(KeyValueStore, :put, fn [:marketing, :cache_globe], published, _opts ->
      assert published.downloads == 0
      assert published.status == :available
      assert published.observed_at == "2035-01-10T00:00:00Z"
      assert published.origins == [origin]
      {:ok, true}
    end)

    assert :ok = CacheGlobeRefreshWorker.perform(%Oban.Job{args: %{}})
  end

  defp snapshot(overrides \\ %{}) do
    CacheGlobe.empty()
    |> Map.merge(%{
      downloads: 42,
      status: :available,
      updated_at: "2035-01-10T12:00:00Z",
      observed_at: "2035-01-10T11:59:00Z",
      origins: [@origin]
    })
    |> Map.merge(overrides)
  end

  defp shared_redis do
    stub(Environment, :redis_url, fn -> "redis://test" end)
    stub(Environment, :redis_conn_name, fn -> :test_redis end)
  end

  defp expect_snapshot(snapshot, origins) do
    expected = CacheGlobe.with_origins(snapshot, origins)

    expect(KeyValueStore, :put, fn [:marketing, :cache_globe], ^expected, opts ->
      assert opts[:persist_across_deployments]
      assert opts[:ttl] == 120_000
      {:ok, true}
    end)
  end

  defp expect_journal(previous, check) do
    expect(Redix, :command, 2, fn :test_redis, command, opts ->
      assert opts[:timeout] == 5000

      case command do
        ["GET", @key] ->
          {:ok, if(previous, do: :erlang.term_to_binary(previous))}

        ["SET", @key, encoded, "EX", 1200] ->
          check.(:erlang.binary_to_term(encoded, [:safe]))
          {:ok, "OK"}
      end
    end)
  end
end
