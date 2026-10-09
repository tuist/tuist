defmodule Tuist.Authentication.SubjectCacheTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Authentication
  alias Tuist.Authentication.SubjectCache

  setup :set_mimic_global

  setup do
    cache = String.to_atom("subjects_#{UUIDv7.generate()}")
    start_supervised!({SubjectCache, cache: cache})
    {:ok, clock} = Agent.start_link(fn -> {0, 1_000_000} end)
    on_exit(fn -> if Process.alive?(clock), do: Agent.stop(clock) end)

    opts = [
      cache: cache,
      ttl: 60_000,
      monotonic: fn -> Agent.get(clock, &elem(&1, 0)) end,
      wall: fn -> Agent.get(clock, &elem(&1, 1)) end
    ]

    %{cache: cache, clock: clock, opts: opts}
  end

  test "warm hits do not load authoritative state or renew the deadline", %{clock: clock, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "token" -> %{subject: :before, expires_at: nil} end)
    expect(Authentication, :authenticated_subject_snapshot, fn "token" -> %{subject: :after, expires_at: nil} end)
    assert {:ok, %{subject: :before, valid_until: 60_000}} = SubjectCache.fetch("token", opts)

    for time <- [1, 20_000, 59_999] do
      Agent.update(clock, fn {_, wall} -> {time, wall} end)
      assert {:ok, %{subject: :before, valid_until: 60_000}} = SubjectCache.fetch("token", opts)
    end

    Agent.update(clock, fn {_, wall} -> {60_000, wall} end)
    assert {:ok, %{subject: :after}} = SubjectCache.fetch("token", opts)
  end

  test "verified expiry caps the deadline and wall-clock jumps cannot bypass it", %{clock: clock, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "token" -> %{subject: :valid, expires_at: 1_005} end)
    expect(Authentication, :authenticated_subject_snapshot, fn "token" -> nil end)
    assert {:ok, %{valid_until: 5_000}} = SubjectCache.fetch("token", opts)
    Agent.update(clock, fn {mono, _} -> {mono, 1_005_000} end)
    assert SubjectCache.fetch("token", opts) == {:ok, nil}
  end

  test "slow fills cannot restart the staleness window", %{clock: clock, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "token" ->
      Agent.update(clock, fn {_, wall} -> {40_000, wall} end)
      %{subject: :valid, expires_at: nil}
    end)

    assert {:ok, %{valid_until: 60_000}} = SubjectCache.fetch("token", opts)
  end

  test "a fill longer than the freshness budget is unavailable, not invalid", %{clock: clock, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "token" ->
      Agent.update(clock, fn {_, wall} -> {60_001, wall} end)
      %{subject: :valid, expires_at: nil}
    end)

    assert SubjectCache.fetch("token", opts) == {:error, :unavailable}
  end

  test "a database outage cannot renew an expired snapshot", %{clock: clock, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "token" -> %{subject: :valid, expires_at: nil} end)

    expect(Authentication, :authenticated_subject_snapshot, fn "token" ->
      raise DBConnection.ConnectionError, "offline"
    end)

    assert {:ok, %{subject: :valid}} = SubjectCache.fetch("token", opts)
    Agent.update(clock, fn {_, wall} -> {59_999, wall} end)
    assert {:ok, %{subject: :valid}} = SubjectCache.fetch("token", opts)
    Agent.update(clock, fn {_, wall} -> {60_000, wall} end)
    assert SubjectCache.fetch("token", opts) == {:error, :unavailable}
  end

  test "a concurrent cold burst resolves one snapshot", %{opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, 1, fn "token" ->
      Process.sleep(30)
      %{subject: :valid, expires_at: nil}
    end)

    results =
      1..64 |> Task.async_stream(fn _ -> SubjectCache.fetch("token", opts) end, max_concurrency: 64) |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, %{subject: :valid}}}, &1))
  end

  test "credential keys are digests and separate different tokens", %{cache: cache, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, fn "read-token" -> %{subject: :read, expires_at: nil} end)
    expect(Authentication, :authenticated_subject_snapshot, fn "write-token" -> %{subject: :write, expires_at: nil} end)
    assert {:ok, %{subject: :read}} = SubjectCache.fetch("read-token", opts)
    assert {:ok, %{subject: :write}} = SubjectCache.fetch("write-token", opts)
    assert Enum.all?(Cachex.keys(cache), &(is_binary(&1) and byte_size(&1) == 32))
    assert Cachex.size(cache) == 2
  end

  test "subject fills and hits bypass suspended shared processes", %{cache: cache, opts: opts} do
    owner = :ets.info(String.to_existing_atom("#{cache}_flights"), :owner)
    courier = Process.whereis(String.to_existing_atom("#{cache}_courier"))
    :sys.suspend(owner)
    :sys.suspend(courier)

    try do
      expect(Authentication, :authenticated_subject_snapshot, 1, fn "token" -> %{subject: :valid, expires_at: nil} end)

      for _ <- 1..100 do
        assert {:ok, %{subject: :valid}} = SubjectCache.fetch("token", opts)
      end
    after
      :sys.resume(owner)
      :sys.resume(courier)
    end
  end

  test "negative authentication is not retained", %{cache: cache, opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, 2, fn "bad" -> nil end)
    assert SubjectCache.fetch("bad", opts) == {:ok, nil}
    assert SubjectCache.fetch("bad", opts) == {:ok, nil}
    assert Cachex.size(cache) == 0
  end

  test "unavailable cache is not an invalid credential" do
    assert SubjectCache.fetch("token", cache: :missing_subject_cache) == {:error, :unavailable}
  end

  test "display invalidation does not evict snapshots", %{opts: opts} do
    expect(Authentication, :authenticated_subject_snapshot, 1, fn "token" -> %{subject: :valid, expires_at: nil} end)
    assert {:ok, %{subject: :valid}} = SubjectCache.fetch("token", opts)
    Cachex.clear(:tuist)
    assert {:ok, %{subject: :valid}} = SubjectCache.fetch("token", opts)
  end
end
