defmodule ScaleEndToEndTokenCache do
  @moduledoc false

  alias ScaleEndToEndController, as: Controller
  alias ScaleEndToEndObserver, as: Observer

  def run(a, b) do
    {_user_id, _project_id, values} = :erpc.call(a, ScaleEndToEnd, :many_cache_credentials, [64])
    backends = [{a, 14_101}, {b, 14_102}]
    for {peer, _port} <- backends, do: :erpc.call(peer, Cachex, :clear, [:token_verification])
    observers = Map.new(backends, fn {peer, _port} -> {peer, :erpc.call(peer, Observer, :start, [])} end)
    expected = Map.new(backends, fn {peer, _port} -> {peer, length(values)} end)

    phase("cold mixed credentials", values, backends, observers, expected, 4)
    phase("warm mixed credentials", values, backends, observers, zeros(backends), 8)

    # Wait for the real production TTL, not a shortened test-only expiration.
    IO.puts("Waiting for the production one-minute proof TTL")
    Process.sleep(60_100)
    phase("expired mixed credentials", values, backends, observers, expected, 4)
    phase("rewarmed mixed credentials", values, backends, observers, zeros(backends), 2)

    :ok = Controller.stop(a)
    {^a, _node} = Controller.start("127.0.0.1", 14_101)
    wait_for_membership(a, b)
    observers = Map.put(observers, a, :erpc.call(a, Observer, :start, []))
    phase("one replica restarted", values, backends, observers, %{a => length(values), b => 0}, 4)
    phase("warm after restart", values, backends, observers, zeros(backends), 2)

    :erpc.call(b, Cachex, :prune, [:token_verification, 1])
    1 = :erpc.call(b, Cachex, :size, [:token_verification])
    phase("one replica evicted proofs", values, backends, observers, %{a => 0, b => length(values) - 1}, 4)
    phase("warm after eviction", values, backends, observers, zeros(backends), 2)
    IO.puts("All diverse-token cache lifecycle checks passed")
  end

  defp zeros(backends), do: Map.new(backends, fn {peer, _port} -> {peer, 0} end)

  defp phase(label, values, backends, observers, expected, repetitions) do
    before = counts(observers)
    probes = Task.async(fn -> probe_health(backends) end)

    requests = for {peer, port} <- backends, value <- values, _ <- 1..repetitions, do: {peer, port, value}

    {duration, responses} =
      :timer.tc(fn ->
        requests
        |> Enum.shuffle()
        |> Task.async_stream(fn {_peer, port, value} -> request(port, "/api/cache/access", value) end,
          max_concurrency: 32,
          timeout: 35_000
        )
        |> Enum.to_list()
      end)

    health = Task.await(probes, 35_000)
    after_counts = counts(observers)
    actual = Map.new(after_counts, fn {peer, count} -> {peer, count - Map.fetch!(before, peer)} end)

    statuses = Enum.frequencies_by(responses, fn {:ok, {status, _}} -> status end)

    if !Enum.all?(responses, &match?({:ok, {200, _}}, &1)),
      do: raise("#{label}: token response statuses #{inspect(statuses)}, bcrypt calls #{inspect(actual)}")

    if !Enum.all?(health, &match?({200, _}, &1)),
      do: raise("#{label}: readiness statuses #{inspect(Enum.frequencies_by(health, &elem(&1, 0)))}")

    if actual != expected, do: raise("#{label}: expected bcrypt calls #{inspect(expected)}, got #{inspect(actual)}")

    latencies = Enum.map(responses, fn {:ok, {_status, elapsed}} -> elapsed end)
    health_latencies = Enum.map(health, fn {_status, elapsed} -> elapsed end)

    IO.puts(
      "PASS: #{label}: #{length(requests)} HTTP requests, #{div(duration, 1000)} ms, " <>
        "bcrypt calls #{inspect(actual)}, request p95 #{percentile(latencies, 0.95)} ms, " <>
        "readiness p95 #{percentile(health_latencies, 0.95)} ms, max #{Enum.max(health_latencies)} ms"
    )
  end

  defp counts(observers),
    do: Map.new(observers, fn {peer, observer} -> {peer, :erpc.call(peer, Observer, :count, [observer, :bcrypt])} end)

  defp request(port, path, value) do
    url = String.to_charlist("http://127.0.0.1:#{port}#{path}")
    headers = if value, do: [{~c"authorization", String.to_charlist("Bearer #{value}")}], else: []

    {duration, {:ok, {{_, status, _}, _, _}}} =
      :timer.tc(fn ->
        :httpc.request(:get, {url, headers}, [timeout: 30_000], body_format: :binary)
      end)

    {status, div(duration, 1000)}
  end

  defp probe_health(backends) do
    for _ <- 1..50, {_peer, port} <- backends do
      Process.sleep(20)
      request(port, "/ready", nil)
    end
  end

  defp percentile(values, fraction), do: values |> Enum.sort() |> Enum.at(ceil(length(values) * fraction) - 1)

  defp wait_for_membership(a, b) do
    Enum.reduce_while(1..200, false, fn _, _ ->
      if :erpc.call(a, Node, :list, []) == [b] and :erpc.call(b, Node, :list, []) == [a] do
        {:halt, true}
      else
        Process.sleep(50)
        {:cont, false}
      end
    end) || raise("Restarted replica did not rejoin")
  end
end
