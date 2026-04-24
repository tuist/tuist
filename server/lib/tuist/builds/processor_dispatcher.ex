defmodule Tuist.Builds.ProcessorDispatcher do
  @moduledoc """
  Picks the least-busy processor replica for a build-processing webhook.

  When `TUIST_PROCESSOR_DISCOVERY_URL` points at a Kubernetes headless Service
  (e.g. `http://tuist-tuist-processor-headless.tuist.svc.cluster.local:4002`),
  this module resolves the hostname to per-pod A records, queries each pod's
  `GET /stats` endpoint in parallel, and returns the URL of the replica with
  the lowest `in_flight` count.

  Falls back to `Tuist.Environment.processor_url/0` (a single URL) when:
    * discovery is not configured
    * DNS resolution returns no addresses
    * every stats probe fails or times out

  Callers must be prepared for `{:ok, nil}` (no URL configured at all — the
  server should process the build locally) and `{:ok, url}` (send the webhook
  there).
  """

  require Logger

  @stats_path "/stats"
  @default_stats_timeout_ms 500

  def pick_url do
    case discovery_url() do
      url when is_binary(url) and url != "" ->
        pick_from_discovery(url)

      _ ->
        {:ok, direct_url()}
    end
  end

  defp pick_from_discovery(discovery_url) do
    %URI{host: host, port: port, scheme: scheme} = URI.parse(discovery_url)
    scheme = scheme || "http"
    port = port || 4002

    case __MODULE__.resolve_pod_ips(host) do
      [] ->
        # DNS returned no records. May be a transient blip during a deploy or
        # a complete outage of the headless Service; either way we prefer any
        # statically configured URL over dropping the job on the floor.
        Logger.warning("Processor discovery returned no pods for #{host}, falling back to processor_url")
        {:ok, direct_url() || discovery_url}

      ips ->
        case pick_least_busy(ips, scheme, port) do
          {:ok, url} -> {:ok, url}
          :error -> {:ok, direct_url() || discovery_url}
        end
    end
  end

  defp pick_least_busy(ips, scheme, port) do
    timeout = stats_timeout_ms()

    results =
      ips
      |> Task.async_stream(
        fn ip -> {ip, __MODULE__.fetch_in_flight("#{scheme}://#{ip}:#{port}", timeout)} end,
        max_concurrency: max(length(ips), 1),
        timeout: timeout + 200,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {ip, {:ok, count}}} -> {ip, count}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case results do
      [] ->
        :error

      ranked ->
        {ip, _count} = Enum.min_by(ranked, fn {_ip, count} -> count end)
        {:ok, "#{scheme}://#{ip}:#{port}"}
    end
  end

  @doc false
  def fetch_in_flight(base_url, timeout_ms) do
    case Req.get(base_url <> @stats_path, receive_timeout: timeout_ms, connect_options: [timeout: timeout_ms]) do
      {:ok, %{status: 200, body: %{"in_flight" => count}}} when is_integer(count) ->
        {:ok, count}

      other ->
        Logger.debug("Processor stats probe failed for #{base_url}: #{inspect(other)}")
        :error
    end
  end

  @doc false
  def resolve_pod_ips(host) when is_binary(host) do
    charlist = String.to_charlist(host)

    case :inet_res.lookup(charlist, :in, :a) do
      [] ->
        # Some resolvers answer on :inet.getaddrs when :inet_res is empty.
        case :inet.getaddrs(charlist, :inet) do
          {:ok, addrs} -> Enum.map(addrs, &(&1 |> :inet.ntoa() |> to_string()))
          _ -> []
        end

      addrs ->
        Enum.map(addrs, &(&1 |> :inet.ntoa() |> to_string()))
    end
  end

  defp discovery_url, do: Tuist.Environment.processor_discovery_url()

  defp direct_url, do: Tuist.Environment.processor_url()

  defp stats_timeout_ms do
    case Tuist.Environment.get([:processor, :stats_timeout_ms]) do
      nil -> @default_stats_timeout_ms
      value when is_binary(value) -> String.to_integer(value)
      value when is_integer(value) -> value
    end
  end
end
