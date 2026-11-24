defmodule Symptoms.Sources.KubernetesEvents do
  @moduledoc """
  Warning events per `(workload, reason)` from the Kubernetes API, every 5
  minutes. The entity is `%{service: "<namespace>/<workload>", kind:
  "k8s_event", key: reason}`; a pod's workload is its name without the
  ReplicaSet hash, the pod suffix or the StatefulSet ordinal.

  It lists `GET /api/v1/events` (core events, `fieldSelector=type=Warning`,
  500 per page, at most `:max_pages` pages, default 20) with the in-cluster
  ServiceAccount: the API server from `KUBERNETES_SERVICE_HOST` and
  `KUBERNETES_SERVICE_PORT`, the token and CA from
  `/var/run/secrets/kubernetes.io/serviceaccount`. The `:kubernetes` option
  (`base_url`, `token`, `ca_file`) overrides them. The ServiceAccount needs
  cluster-wide `list` on `events`.

  An event object counts in the window when it was last observed in it
  (`series.lastObservedTime`, `lastTimestamp` or `eventTime`). It adds its
  full `count` when it also started in the window, and 1 otherwise, since
  earlier occurrences were counted in earlier windows.

  Streams:

  - `"k8s.event_negative_binomial"` (`:platform_events`): the negative
    binomial residual of the count against the pair's baseline (same stream
    name: `%{mean, alpha, n}` per 5-minute window, or a list of the pair's
    stored counts at the same hour of week, which `Symptoms.Baselines`
    returns and this source fits with `Statistics.fit_negative_binomial/1`).
    A known pair without stored counts yet is fitted on an empty history, so
    its counts start to accumulate; calibration ranks the residual against
    its own history. Expected pairs (`:entities`) without events get a record
    with count 0.
  - `"k8s.event_novelty"` (`:novelty`): a pair the catalogue does not know.

  Chronic reasons never become evidence or novelty; they go to the injected
  `:digest` function, `([%{entity, count, examples}]) -> any()`, for the daily
  digest. `:chronic` lists `{reason, :always | :known}`, default
  `DNSConfigForming` always and `Unhealthy` when the pair is known (a known
  pod's probe failing is chronic; a new one is novelty).
  """

  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Sources.Support

  @service_account "/var/run/secrets/kubernetes.io/serviceaccount"
  @page_size 500
  @default_max_pages 20
  @default_chronic [{"DNSConfigForming", :always}, {"Unhealthy", :known}]

  @impl true
  def name, do: "k8s"

  @impl true
  def window_seconds, do: 300

  @impl true
  def collect(window, opts) do
    case list_events(opts) do
      {:ok, events} ->
        counts = count(events, window, opts)
        {chronic, counted} = Enum.split_with(counts, fn {entity, _} -> chronic?(entity, opts) end)
        digest(chronic, opts)

        quiet =
          for %{kind: "k8s_event"} = entity <- Support.expected_entities(opts),
              not Map.has_key?(counts, entity),
              not chronic?(entity, opts),
              do: {entity, %{count: 0, examples: []}}

        {:ok, Enum.flat_map(counted ++ quiet, &records(&1, window, opts))}

      {:error, _reason} ->
        {:unknown, Support.expected_entities(opts)}
    end
  end

  @doc false
  def count(events, window, opts) do
    finish = Support.finish(window)

    events
    |> Enum.flat_map(&in_window(&1, window.start, finish, opts))
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {entity, rows} ->
      {entity,
       %{
         count: rows |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
         examples: rows |> Enum.map(&elem(&1, 2)) |> Enum.filter(&is_binary/1) |> Enum.take(3)
       }}
    end)
  end

  defp in_window(event, start, finish, opts) do
    last = last_observed(event)

    if is_integer(last) and last >= start and last < finish do
      first = timestamp(event["firstTimestamp"]) || timestamp(event["eventTime"]) || last
      occurrences = if first >= start, do: occurrences(event), else: 1
      [{entity(event, opts), occurrences, get_in(event, ["metadata", "uid"])}]
    else
      []
    end
  end

  defp records({entity, %{count: count, examples: examples}}, window, opts) do
    impact = %{unit: "events_per_min", rate: Support.per_minute(count, window.seconds)}

    cond do
      fit = fit(Support.baseline(opts, "k8s.event_negative_binomial", entity), entity, opts) ->
        [
          Support.record(window, entity,
            phenomenon: :platform_events,
            source: "k8s.event_negative_binomial",
            statistic: Statistics.negative_binomial_residual(count, fit),
            observed: count,
            expected: fit.mean,
            n: count,
            impact: impact,
            examples: examples
          )
        ]

      count > 0 and not Support.known?(opts, entity) ->
        Support.report_discovered(opts, [entity])

        [
          Support.record(window, entity,
            phenomenon: :novelty,
            source: "k8s.event_novelty",
            statistic: count * 1.0,
            observed: count,
            n: count,
            impact: impact,
            examples: examples
          )
        ]

      true ->
        []
    end
  end

  defp fit(%{mean: _} = fit, _entity, _opts), do: fit
  defp fit([_ | _] = counts, _entity, _opts), do: Statistics.fit_negative_binomial(counts)
  defp fit(_none, entity, opts), do: if(Support.known?(opts, entity), do: Statistics.fit_negative_binomial([]))

  defp chronic?(entity, opts) do
    case List.keyfind(Keyword.get(opts, :chronic, @default_chronic), entity.key, 0) do
      {_reason, :always} -> true
      {_reason, :known} -> Support.known?(opts, entity)
      nil -> false
    end
  end

  defp digest([], _opts), do: :ok

  defp digest(chronic, opts) do
    case Keyword.get(opts, :digest) do
      fun when is_function(fun, 1) -> fun.(Enum.map(chronic, fn {entity, item} -> Map.put(item, :entity, entity) end))
      _ -> :ok
    end
  end

  @doc "The `(workload, reason)` entity of an event."
  @spec entity(map(), keyword()) :: map()
  def entity(event, opts) do
    object = event["involvedObject"] || event["regarding"] || %{}
    namespace = object["namespace"] || get_in(event, ["metadata", "namespace"]) || "cluster"

    Support.entity(
      opts,
      "#{namespace}/#{workload(object["kind"], object["name"] || "")}",
      "k8s_event",
      event["reason"] || "Unknown"
    )
  end

  @doc """
  The workload of an object: for a pod, its name without the ReplicaSet hash
  and pod suffix (`server-7d9f8b6c5d-x2x4z` → `server`), the DaemonSet or Job
  suffix (`alloy-x2x4z` → `alloy`) or the StatefulSet ordinal (`pg-1` → `pg`);
  other kinds keep their name, prefixed with the kind in lowercase.
  """
  @spec workload(String.t() | nil, String.t()) :: String.t()
  def workload("Pod", name) do
    cond do
      match = Regex.run(~r/^(.+)-[a-z0-9]{8,10}-[a-z0-9]{5}$/, name) -> Enum.at(match, 1)
      match = Regex.run(~r/^(.+)-[a-z0-9]{5}$/, name) -> Enum.at(match, 1)
      match = Regex.run(~r/^(.+)-\d+$/, name) -> Enum.at(match, 1)
      true -> name
    end
  end

  def workload(kind, name) when is_binary(kind), do: "#{String.downcase(kind)}/#{name}"
  def workload(_kind, name), do: name

  defp last_observed(event) do
    timestamp(get_in(event, ["series", "lastObservedTime"])) || timestamp(event["lastTimestamp"]) ||
      timestamp(event["eventTime"])
  end

  defp occurrences(event) do
    case get_in(event, ["series", "count"]) || event["count"] do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> DateTime.to_unix(at)
      _ -> nil
    end
  end

  defp timestamp(_value), do: nil

  defp list_events(opts) do
    with {:ok, client} <- client(opts) do
      list_pages(client, nil, [], Keyword.get(opts, :max_pages, @default_max_pages))
    end
  end

  defp list_pages(_client, _continue, _acc, 0), do: {:error, :too_many_events}

  defp list_pages(client, continue, acc, pages_left) do
    params = Enum.reject([limit: @page_size, fieldSelector: "type=Warning", continue: continue], &is_nil(elem(&1, 1)))

    request =
      Req.new(
        method: :get,
        url: client.base_url <> "/api/v1/events",
        auth: {:bearer, client.token},
        headers: [{"accept", "application/json"}],
        params: params,
        retry: false,
        redirect: false,
        receive_timeout: 30_000,
        connect_options: client.connect_options
      )

    case Req.request(request) do
      {:ok, %Req.Response{status: 200, body: %{"items" => items} = body}} when is_list(items) ->
        case get_in(body, ["metadata", "continue"]) do
          next when is_binary(next) and next != "" -> list_pages(client, next, acc ++ items, pages_left - 1)
          _ -> {:ok, acc ++ items}
        end

      {:ok, %Req.Response{}} ->
        {:error, :upstream_error}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  defp client(opts) do
    config = Keyword.get(opts, :kubernetes, [])
    host = System.get_env("KUBERNETES_SERVICE_HOST")
    port = System.get_env("KUBERNETES_SERVICE_PORT", "443")
    base_url = config[:base_url] || (host && "https://#{host}:#{port}")
    token = config[:token] || read(Path.join(@service_account, "token"))
    ca_file = config[:ca_file] || Path.join(@service_account, "ca.crt")

    if is_binary(base_url) and is_binary(token) and token != "" do
      connect_options =
        if File.exists?(ca_file), do: [timeout: 10_000, transport_opts: [cacertfile: ca_file]], else: [timeout: 10_000]

      {:ok, %{base_url: String.trim_trailing(base_url, "/"), token: String.trim(token), connect_options: connect_options}}
    else
      {:error, :not_configured}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      _ -> nil
    end
  end
end
