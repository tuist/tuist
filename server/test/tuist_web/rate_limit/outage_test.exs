defmodule TuistWeb.RateLimit.OutageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.PromEx.RateLimit, as: RateLimitMetrics
  alias TuistTestSupport.TelemetryCapture
  alias TuistWeb.RateLimit
  alias TuistWeb.RateLimit.InMemory
  alias TuistWeb.RateLimit.PersistentFixedWindow
  alias TuistWeb.RateLimit.PersistentTokenBucket

  setup do
    stub(Environment, :redis_url, fn -> "redis://unavailable" end)
    stub(Environment, :rate_limit_fallback_replicas, fn -> 5 end)
    stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> exit(:noproc) end)
    %{key: "outage:#{UUIDv7.generate()}", window: System.system_time(:millisecond) * 2}
  end

  test "the local budget is atomic under concurrent requests", %{key: key, window: window} do
    results =
      1..400
      |> Task.async_stream(fn _ -> RateLimit.hit(key, limit: 100, window: window, failure_policy: :local) end,
        max_concurrency: 64
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:allow, _}, &1)) == 20
    assert Enum.count(results, &match?({:deny, _}, &1)) == 380
  end

  test "local outage hits do not broadcast to peers", %{key: key, window: window} do
    owner = self()
    :ok = Phoenix.PubSub.subscribe(Tuist.PubSub, "__ratelimit")

    stub(InMemory, :hit, fn actual_key, scale, limit, increment ->
      send(owner, {:broadcast_path, actual_key})
      Mimic.call_original(InMemory, :hit, [actual_key, scale, limit, increment])
    end)

    assert {:allow, 1} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
    refute_received {:broadcast_path, _}
    refute_receive {:fixed_window, {:fallback, ^key}, ^window, _}
  end

  test "raw in-memory counters cannot consume the outage namespace", %{key: key, window: window} do
    for _ <- 1..100, do: InMemory.Local.hit(key, window, 100)
    assert {:allow, 1} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
  end

  test "configured larger fleets reduce the budget", %{key: key, window: window} do
    stub(Environment, :rate_limit_fallback_replicas, fn -> 10 end)

    for count <- 1..10,
        do: assert({:allow, ^count} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local))

    assert {:deny, _} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
  end

  for invalid <- [0, 1, 4, -1, nil, "5", 5.0] do
    @invalid invalid
    test "invalid replica allowance #{inspect(invalid)} fails closed", %{key: key, window: window} do
      stub(Environment, :rate_limit_fallback_replicas, fn -> @invalid end)
      assert {:deny, ^window} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
    end
  end

  test "increments spend the reduced budget rather than one admission each", %{key: key, window: window} do
    opts = [limit: 100, window: window, increment: 7, failure_policy: :local]
    assert {:allow, 7} = RateLimit.hit(key, opts)
    assert {:allow, 14} = RateLimit.hit(key, opts)
    assert {:deny, _} = RateLimit.hit(key, opts)
  end

  test "local table unavailability denies and is observable", %{key: key, window: window} do
    stub(InMemory.Local, :hit, fn _, _, _, _ -> raise ArgumentError, "table unavailable" end)
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :rate_limit, :shared_failure]])
    assert {:deny, ^window} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)

    assert_receive {[:tuist, :rate_limit, :shared_failure], ^ref, %{count: 1},
                    %{algorithm: :fixed_window, policy: :local, outcome: :deny}}
  end

  test "local process exits deny rather than escaping the fallback", %{key: key, window: window} do
    stub(InMemory.Local, :hit, fn _, _, _, _ -> exit(:noproc) end)
    assert {:deny, ^window} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
  end

  for failure <- [:redis_error, :connection_error, :match_error, :exit], policy <- [:deny, :local] do
    @failure failure
    @policy policy
    test "#{failure} uses the #{@policy} policy", %{key: key, window: window} do
      stub(PersistentFixedWindow, :hit, fn _, _, _, _ ->
        case @failure do
          :redis_error -> raise Redix.Error, message: "READONLY replica"
          :connection_error -> raise Redix.ConnectionError, reason: :closed
          :match_error -> raise MatchError, term: {:error, :closed}
          :exit -> exit(:noproc)
        end
      end)

      result = RateLimit.hit(key, limit: 100, window: window, failure_policy: @policy)
      if @policy == :local, do: assert(result == {:allow, 1}), else: assert(result == {:deny, window})
    end
  end

  test "unrelated programming exceptions are not disguised as outages", %{key: key, window: window} do
    stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> raise "unexpected defect" end)
    assert_raise RuntimeError, "unexpected defect", fn -> RateLimit.hit(key, limit: 100, window: window) end
  end

  test "shared denials never grant a second local budget", %{key: key, window: window} do
    stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> {:deny, 123} end)
    reject(InMemory.Local, :hit, 4)
    assert {:deny, 123} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
  end

  for unexpected <- [nil, false, {:error, :timeout}, {:allow, -1}, {:allow, 1.0}, {:deny, "later"}] do
    @unexpected unexpected
    test "unexpected shared result #{inspect(unexpected)} fails closed", %{key: key, window: window} do
      stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> @unexpected end)
      assert {:deny, ^window} = RateLimit.hit(key, limit: 100, window: window)
    end
  end

  test "recovery and another outage do not reset the local budget", %{key: key, window: window} do
    opts = [limit: 10, window: window, failure_policy: :local]
    assert {:allow, 1} = RateLimit.hit(key, opts)
    stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> {:allow, 1} end)
    assert {:allow, 1} = RateLimit.hit(key, opts)
    stub(PersistentFixedWindow, :hit, fn _, _, _, _ -> exit(:noproc) end)
    assert {:allow, 2} = RateLimit.hit(key, opts)
    assert {:deny, _} = RateLimit.hit(key, opts)
  end

  test "both failure algorithms emit only bounded policy and outcome labels", %{key: key, window: window} do
    ref = TelemetryCapture.attach_event_handlers([[:tuist, :rate_limit, :shared_failure]])
    assert {:allow, 1} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
    assert_receive {[:tuist, :rate_limit, :shared_failure], ^ref, %{count: 1}, metadata}
    assert metadata == %{algorithm: :fixed_window, policy: :local, outcome: :allow}

    stub(PersistentTokenBucket, :hit, fn _, _, _, _ -> raise Redix.ConnectionError, reason: :timeout end)
    assert {:deny, 1000} = RateLimit.hit(key, algorithm: :token_bucket, capacity: 100, refill_rate: 1)
    assert_receive {[:tuist, :rate_limit, :shared_failure], ^ref, %{count: 1}, metadata}
    assert metadata == %{algorithm: :token_bucket, policy: :deny, outcome: :deny}
  end

  test "shared limiter failure events reach the Prometheus reporter", %{key: key, window: window} do
    %{metrics: metrics} = RateLimitMetrics.event_metrics([])
    name = String.to_atom("rate_limit_metrics_#{UUIDv7.generate()}")
    start_supervised!({Peep, name: name, metrics: metrics, storage: :striped})
    assert {:allow, 1} = RateLimit.hit(key, limit: 100, window: window, failure_policy: :local)
    text = Tuist.PromEx.StripedPeep.scrape(name)
    assert text =~ "tuist_rate_limit_shared_failure_total"
    assert text =~ ~s(algorithm="fixed_window")
    assert text =~ ~s(policy="local")
    assert text =~ ~s(outcome="allow")
    refute text =~ key
  end

  test "shared limiter failure metrics are registered without credential labels" do
    assert RateLimitMetrics in Tuist.PromEx.plugins()
    %{metrics: [metric]} = RateLimitMetrics.event_metrics([])
    assert metric.event_name == [:tuist, :rate_limit, :shared_failure]
    assert metric.tags == [:algorithm, :policy, :outcome]
  end
end
