defmodule Pulse.Auth.JWKS do
  @moduledoc """
  Node-local cache of signing keys for workload identity trust entries whose
  key source is a JWKS URL.

  Each instance fetches independently; the cache is a disposable optimization,
  never shared state. Keys are refreshed every `refresh_interval_seconds` and
  stay usable for three intervals after the last successful fetch, so a brief
  issuer outage does not reject traffic but a removed key stops verifying
  within a bounded time. An unknown `kid` triggers an on-demand refresh at
  most once per `min_refresh_ms` per source, so forged tokens cannot amplify
  requests to the issuer.

  Requests use the configured CA bundle (or the system trust store), present
  the contents of `token_file` as a bearer credential when configured, cap the
  response at 1 MiB and time out after 5 s. Credentials are never logged.
  """

  use GenServer

  alias Pulse.Auth.WorkloadIdentity
  alias Pulse.Runtime

  require Logger

  @max_body_bytes 1_048_576
  @timeout_ms 5_000
  @min_refresh_ms 30_000

  @doc "Children to start: the cache only runs when a URL key source is configured."
  def children do
    if Enum.any?(WorkloadIdentity.trust(), & &1.jwks_url), do: [__MODULE__], else: []
  end

  def start_link(opts \\ []), do: Runtime.server_start(__MODULE__, opts, name: __MODULE__)

  @doc "Fresh cached keys for a URL-sourced `entry`, or `:unavailable`."
  def cached(entry) do
    table = Runtime.table(__MODULE__)
    now = System.monotonic_time(:millisecond)

    with ref when ref != :undefined <- :ets.whereis(table),
         [{_name, source, keys, expires_at}] when source == entry.jwks_url and expires_at > now <-
           :ets.lookup(ref, entry.name) do
      keys
    else
      _ -> :unavailable
    end
  end

  @doc "Asks for a rate-limited refresh of `entry` and waits for it."
  def refresh(entry) do
    case Runtime.whereis(__MODULE__) do
      nil -> :unavailable
      pid -> GenServer.call(pid, {:refresh, entry}, 3 * @timeout_ms)
    end
  catch
    :exit, _ -> :unavailable
  end

  @impl true
  def init(opts) do
    table = :ets.new(Runtime.table(__MODULE__), [:named_table, :protected, read_concurrency: true])

    for entry <- Keyword.get_lazy(opts, :trust, &WorkloadIdentity.trust/0),
        entry.jwks_url,
        do: send(self(), {:scheduled, entry})

    {:ok,
     %{
       table: table,
       attempts: %{},
       http_options: Keyword.get(opts, :http_options, []),
       min_refresh_ms: Keyword.get(opts, :min_refresh_ms, @min_refresh_ms)
     }}
  end

  @impl true
  def handle_info({:scheduled, entry}, state) do
    Process.send_after(self(), {:scheduled, entry}, entry.jwks_url.refresh_interval_seconds * 1000)
    {:noreply, fetch(entry, state)}
  end

  @impl true
  def handle_call({:refresh, entry}, _from, state) do
    last = Map.get(state.attempts, entry.name)

    if last && System.monotonic_time(:millisecond) - last < state.min_refresh_ms,
      do: {:reply, :ok, state},
      else: {:reply, :ok, fetch(entry, state)}
  end

  defp fetch(%{jwks_url: source} = entry, state) do
    now = System.monotonic_time(:millisecond)

    with {:ok, body} <- get(source, state.http_options),
         {:ok, keys} <- WorkloadIdentity.parse_jwks(body) do
      expires_at = now + 3 * source.refresh_interval_seconds * 1000
      :ets.insert(state.table, {entry.name, source, keys, expires_at})
    else
      {:error, reason} ->
        Logger.warning("workload identity JWKS refresh failed for trust #{entry.name}: #{inspect(reason)}")
    end

    put_in(state.attempts[entry.name], now)
  end

  defp get(source, http_options) do
    with {:ok, headers} <- credential(source) do
      tls = if source.ca_file, do: [cacertfile: source.ca_file], else: []

      options =
        Keyword.merge(
          [
            url: source.url,
            headers: headers,
            retry: false,
            redirect: false,
            decode_body: false,
            receive_timeout: @timeout_ms,
            connect_options: [timeout: @timeout_ms, transport_opts: tls],
            into: &collect/2
          ],
          http_options
        )

      case Req.get(options) do
        {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
        {:ok, %{status: 200}} -> {:error, :response_too_large}
        {:ok, %{status: status}} -> {:error, {:http_status, status}}
        {:error, exception} -> {:error, {:request_failed, Exception.message(exception)}}
      end
    end
  end

  defp credential(%{token_file: nil}), do: {:ok, []}

  defp credential(%{token_file: path}) do
    case File.read(path) do
      {:ok, token} when byte_size(token) > 0 -> {:ok, [{"authorization", "Bearer " <> String.trim(token)}]}
      _ -> {:error, :token_file_unreadable}
    end
  end

  defp collect({:data, data}, {request, response}) do
    body = response.body <> data

    if byte_size(body) > @max_body_bytes,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body}}}
  end
end
