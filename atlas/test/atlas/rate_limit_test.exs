defmodule Atlas.RateLimitTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.RateLimit
  alias Ecto.Adapters.SQL.Sandbox

  test "shares attempts across callers rather than process-local buckets" do
    key = unique_key()
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 2)

    task = Task.async(fn -> RateLimit.hit(key, 60_000, 2) end)
    assert {:allow, 2} = Task.await(task)
    assert {:deny, remaining} = RateLimit.hit(key, 60_000, 2)
    assert remaining in 1..60_000
  end

  test "concurrent independent database connections share one allowance" do
    key = unique_key()
    hash = key_hash(key)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> Repo.query!("DELETE FROM rate_limit_buckets WHERE key_hash = $1", [hash]) end)
    end)

    results =
      1..20
      |> Task.async_stream(
        fn _ ->
          Sandbox.unboxed_run(Repo, fn -> RateLimit.hit(key, 60_000, 3) end)
        end,
        max_concurrency: 2,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.sort(for {:allow, count} <- results, do: count) == [1, 2, 3]
    assert Enum.count(results, &match?({:deny, _}, &1)) == 17
  end

  test "an expired bucket starts a fresh window and counter" do
    key = unique_key()
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 1)
    expire_bucket(key)
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 1)
  end

  test "denied attempts do not extend the window or overflow the counter" do
    key = unique_key()
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 1)
    original = Repo.query!("SELECT expires_at FROM rate_limit_buckets WHERE key_hash = $1", [key_hash(key)]).rows

    for _ <- 1..10, do: assert({:deny, _remaining} = RateLimit.hit(key, 60_000, 1))

    assert %{rows: [[2, expires_at]]} =
             Repo.query!("SELECT attempts, expires_at FROM rate_limit_buckets WHERE key_hash = $1", [key_hash(key)])

    assert original == [[expires_at]]
  end

  test "keys are hashed and different windows are isolated" do
    key = unique_key()
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 1)
    assert {:allow, 1} = RateLimit.hit(key, 3_600_000, 1)

    assert %{rows: rows} =
             Repo.query!("SELECT key_hash FROM rate_limit_buckets WHERE key_hash = ANY($1)", [
               [key_hash(key), key_hash(key, 3_600_000)]
             ])

    assert length(rows) == 2
    assert Enum.all?(rows, fn [hash] -> byte_size(hash) == 32 and hash != key end)
  end

  test "cleanup only removes expired buckets" do
    key = unique_key()
    assert {:allow, 1} = RateLimit.hit(key, 60_000, 1)
    assert :ok = RateLimit.prune_expired()
    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM rate_limit_buckets WHERE key_hash = $1", [key_hash(key)])
    expire_bucket(key)
    assert :ok = RateLimit.prune_expired()
    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM rate_limit_buckets WHERE key_hash = $1", [key_hash(key)])
  end

  test "database errors fail closed" do
    expect(Repo, :query, fn _sql, _params -> {:error, :unavailable} end)
    assert {:deny, 60_000} = RateLimit.hit(unique_key(), 60_000, 1)
  end

  defp unique_key, do: "rate-limit-#{System.unique_integer([:positive])}"
  defp key_hash(key, window \\ 60_000), do: :crypto.hash(:sha256, "#{window}:#{key}")

  defp expire_bucket(key) do
    Repo.query!(
      "UPDATE rate_limit_buckets SET expires_at = statement_timestamp() - interval '1 second' WHERE key_hash = $1",
      [
        key_hash(key)
      ]
    )
  end
end
