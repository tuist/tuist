defmodule Atlas.Engineering.Errors.PulseMirror do
  @moduledoc """
  Opt-in, best-effort parallel collection, never an Atlas delivery authority.

  Admission uses bounded ETS slots, not casts or database writes. Only scrubbed
  JSON is queued. One sender owns at most 64 pending events (128 KiB each),
  including retries; process loss loses pending copies. No shutdown flush.
  """
  use GenServer, restart: :temporary

  alias Atlas.Engineering.Errors.PulseMirror.Config

  @slots 64
  @max_bytes 131_072
  @ttl_ms 60_000
  @finch __MODULE__.Finch
  @counters [:delivered, :retried, :full, :expired, :rejected, :failed]
  @private ~r/user|request|headers|authorization|cookie|password|passwd|secret|token|api.?key|sentry.?key|dsn|^sentry\.interfaces\.http$/i

  def children do
    case Config.options() do
      [] ->
        []

      [routes: []] ->
        []

      opts ->
        [
          Supervisor.child_spec(
            {Finch, name: @finch, pools: %{default: [size: 1, count: 1, conn_opts: [transport_opts: [timeout: 500]]]}},
            id: @finch,
            restart: :temporary
          ),
          {__MODULE__, opts}
        ]
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Always returns :ok. Neither Pulse nor queue failures change Atlas acceptance."
  def offer(row) do
    offer_to(Config.table(), row)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp offer_to(:undefined, _row), do: :ok

  defp offer_to(table, row) do
    case :ets.lookup(table, {:route, row.project_id, empty_domain(row.domain_id)}) do
      [{_, target}] ->
        if :ets.info(table, :size) >= :ets.lookup_element(table, :full_size, 2),
          do: count(table, :full),
          else: admit(table, target, row)

      [] ->
        :ok
    end
  end

  defp admit(table, target, row) when byte_size(row.payload) <= @max_bytes do
    payload =
      row.payload
      |> Jason.decode!()
      |> scrub(0)
      |> Map.put("event_id", String.replace(row.event_id, "-", ""))
      |> Map.put("timestamp", DateTime.to_iso8601(row.timestamp))
      |> Map.put("project", target.project)
      |> Map.put("atlas_project_id", row.project_id)
      |> Map.put("atlas_domain_id", empty_domain(row.domain_id))

    body = Jason.encode!(payload)

    if byte_size(body) <= @max_bytes do
      now = System.monotonic_time(:millisecond)
      entry = {body, target, 0, now, now}

      # Fixed probes bound admission work even with concurrent producers.
      if !Enum.any?(0..(@slots - 1), &:ets.insert_new(table, {&1, entry})), do: count(table, :full)
    else
      count(table, :rejected)
    end
  rescue
    _ -> count(table, :rejected)
  catch
    :too_deep -> count(table, :rejected)
  end

  defp admit(table, _target, _row), do: count(table, :rejected)

  # Drop the whole contextual objects, including legacy aliases at any depth.
  # Strings (messages, source, breadcrumbs) still require upstream PII scrubbing.
  defp scrub(_value, depth) when depth > 32, do: throw(:too_deep)

  defp scrub(value, depth) when is_map(value) do
    Map.new(value, fn {key, val} ->
      {key, if(Regex.match?(@private, key), do: "[Filtered]", else: scrub(val, depth + 1))}
    end)
  end

  defp scrub([key, value], depth) when is_binary(key) do
    [key, if(Regex.match?(@private, key), do: "[Filtered]", else: scrub(value, depth + 1))]
  end

  defp scrub(value, depth) when is_list(value), do: Enum.map(value, &scrub(&1, depth + 1))
  defp scrub(value, _depth), do: value

  @doc "Node-local, fixed-cardinality counters; no payloads, keys or remote error strings."
  def stats do
    table = Config.table()
    Map.new(@counters, fn key -> {key, :ets.lookup_element(table, key, 2)} end)
  rescue
    _ -> %{}
  end

  @impl true
  def init(opts) do
    routes = validate_routes!(Keyword.fetch!(opts, :routes))
    table_opts = [:set, :public, write_concurrency: true]
    table_opts = if Keyword.get(opts, :named, true), do: [:named_table | table_opts], else: table_opts
    table = :ets.new(__MODULE__, table_opts)
    :ets.insert(table, Enum.map(routes, fn {{project, domain}, target} -> {{:route, project, domain}, target} end))
    :ets.insert(table, Enum.map(@counters, &{&1, 0}))
    :ets.insert(table, {:full_size, @slots + map_size(routes) + length(@counters) + 1})
    send(self(), :tick)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.monotonic_time(:millisecond)

    _sent? =
      state.table
      |> :ets.select([{{:"$1", :"$2"}, [{:is_integer, :"$1"}], [{{:"$1", :"$2"}}]}])
      |> Enum.sort_by(fn {_slot, {_, _, _, inserted, _}} -> inserted end)
      |> Enum.reduce(false, fn {slot, {_, _, _, inserted, due} = entry}, sent? ->
        cond do
          now - inserted >= @ttl_ms ->
            :ets.delete(state.table, slot)
            count(state.table, :expired)
            sent?

          !sent? and due <= now ->
            deliver(state.table, slot, entry)
            true

          true ->
            sent?
        end
      end)

    Process.send_after(self(), :tick, 100)
    {:noreply, state}
  end

  defp deliver(table, slot, {body, target, attempts, inserted, _due}) do
    # Hard wall-clock deadline, including pool wait, DNS, connect and response.
    # No more than one task or HTTP request per mirror, and no automatic Req retries.
    task = Task.async(fn -> post(target, body) end)
    result = Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill)

    case result do
      {:ok, :ok} ->
        :ets.delete(table, slot)
        count(table, :delivered)

      {:ok, :permanent} ->
        :ets.delete(table, slot)
        count(table, :failed)

      _ when attempts >= 2 ->
        :ets.delete(table, slot)
        count(table, :failed)

      _ ->
        delay = if attempts == 0, do: 1_000, else: 5_000
        due = System.monotonic_time(:millisecond) + delay
        :ets.insert(table, {slot, {body, target, attempts + 1, inserted, due}})
        count(table, :retried)
    end
  end

  defp post(target, body) do
    result =
      Req.post(target.url,
        body: body,
        headers: [{"content-type", "application/json"}, {"x-sentry-auth", "Sentry sentry_key=#{target.key}"}],
        finch: [name: @finch, pool_timeout: 500],
        retry: false,
        redirect: false,
        receive_timeout: 1_000,
        # Ignore bodies rather than buffering untrusted diagnostics (or credentials).
        into: fn {:data, _data}, acc -> {:cont, acc} end
      )

    case result do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} when status in [408, 429] or status >= 500 -> :retry
      {:ok, _} -> :permanent
      _ -> :retry
    end
  rescue
    _ -> :retry
  catch
    _, _ -> :retry
  end

  defp count(table, reason), do: :ets.update_counter(table, reason, {2, 1})
  defp empty_domain(""), do: nil
  defp empty_domain(domain), do: domain

  @doc "Validates exact operator-owned Atlas project/domain to Pulse project mappings."
  def validate_routes!(routes) when is_list(routes) and length(routes) in 1..256 do
    pairs = Enum.map(routes, &validate_route!/1)
    result = Map.new(pairs)
    if map_size(result) != length(pairs), do: raise(ArgumentError, "duplicate Pulse mirror source")
    result
  end

  def validate_routes!(_), do: raise(ArgumentError, "invalid Pulse mirror routes")

  defp validate_route!(route) do
    with %{"atlas_project_id" => source, "pulse_project_id" => project, "url" => url, "public_key" => key} <- route,
         true <- Map.keys(route) -- ~w(atlas_project_id atlas_domain_id pulse_project_id url public_key) == [],
         {:ok, ^source} <- Ecto.UUID.cast(source),
         domain = route["atlas_domain_id"],
         true <- is_nil(domain) or match?({:ok, ^domain}, Ecto.UUID.cast(domain)),
         true <- is_binary(project) and Regex.match?(~r/\A[0-9]{1,32}\z/, project),
         true <- is_binary(key) and Regex.match?(~r/\A[a-zA-Z0-9_-]{1,256}\z/, key),
         true <- is_binary(url) and byte_size(url) <= 2_048,
         {:ok, %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil, path: path}} <- URI.new(url),
         true <- scheme in ["http", "https"] and host not in [nil, ""] and path in [nil, "", "/"] do
      {{source, domain}, %{project: project, key: key, url: String.trim_trailing(url, "/") <> "/api/#{project}/store/"}}
    else
      _ -> raise ArgumentError, "invalid Pulse mirror route"
    end
  end
end
