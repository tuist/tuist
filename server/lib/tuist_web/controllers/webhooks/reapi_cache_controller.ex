defmodule TuistWeb.Webhooks.ReapiCacheController do
  use TuistWeb, :controller

  alias Tuist.Projects
  alias Tuist.ReapiCache
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  require Logger

  def handle(conn, %{"events" => events}) when is_list(events) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      cache_endpoint = conn.assigns.cache_endpoint

      bazel_events = Enum.filter(events, &bazel_event?/1)

      projects_map =
        bazel_events
        |> Enum.map(&"#{&1["account_handle"]}/#{&1["project_handle"]}")
        |> Enum.uniq()
        |> Projects.projects_by_full_handles()

      cache_events =
        Enum.flat_map(bazel_events, fn event ->
          case cache_event(event, projects_map, cache_endpoint) do
            {:ok, cache_event} ->
              [cache_event]

            {:error, :project_not_found, full_handle} ->
              Logger.warning("Project not found for Bazel remote cache event: #{full_handle}")
              []

            {:error, :invalid, full_handle} ->
              Logger.warning("Invalid Bazel remote cache event for project: #{full_handle}")
              []
          end
        end)

      ReapiCache.create_cache_events(cache_events)

      conn
      |> put_status(:accepted)
      |> json(%{accepted: length(cache_events), rejected: length(bazel_events) - length(cache_events)})
      |> halt()
    end
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end

  defp bazel_event?(%{"client_kind" => "bazel"}), do: true
  defp bazel_event?(_), do: false

  defp cache_event(event, projects_map, cache_endpoint) do
    with %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "operation" => operation,
           "outcome" => outcome,
           "action_digest" => action_digest,
           "size" => size,
           "duration_ms" => duration_ms
         } <- event,
         true <- is_binary(account_handle) and is_binary(project_handle) do
      full_handle = "#{account_handle}/#{project_handle}"

      with %{id: project_id, build_system: :bazel} <- Map.get(projects_map, full_handle),
           true <- valid_event?(operation, outcome, action_digest, size, duration_ms, Map.get(event, "observed_at_ms")) do
        {:ok,
         %{
           client_kind: "bazel",
           operation: operation,
           outcome: outcome,
           action_digest: action_digest,
           size: size,
           duration_ms: duration_ms,
           observed_at: observed_at(event),
           invocation_id: optional_string(event, "invocation_id"),
           action_mnemonic: optional_string(event, "action_mnemonic"),
           target_label: optional_string(event, "target_label"),
           configuration_id: optional_string(event, "configuration_id"),
           project_id: project_id,
           account_handle: account_handle,
           project_handle: project_handle,
           cache_endpoint: cache_endpoint
         }}
      else
        nil -> {:error, :project_not_found, full_handle}
        false -> {:error, :invalid, full_handle}
        %{} -> {:error, :invalid, full_handle}
      end
    else
      _ -> {:error, :invalid, "unknown"}
    end
  end

  defp valid_event?(operation, outcome, action_digest, size, duration_ms, observed_at_ms) do
    operation in ["action_cache", "cas"] and
      outcome in ["hit", "miss", "write"] and is_binary(action_digest) and is_integer(size) and size >= 0 and
      is_integer(duration_ms) and duration_ms >= 0 and valid_observed_at?(observed_at_ms)
  end

  defp valid_observed_at?(nil), do: true

  defp valid_observed_at?(observed_at_ms) when is_integer(observed_at_ms),
    do: match?({:ok, _}, DateTime.from_unix(observed_at_ms, :millisecond))

  defp valid_observed_at?(_), do: false

  defp observed_at(event) do
    case Map.get(event, "observed_at_ms") do
      observed_at_ms when is_integer(observed_at_ms) ->
        {:ok, observed_at} = DateTime.from_unix(observed_at_ms, :millisecond)
        with_microsecond_precision(observed_at)

      _ ->
        DateTime.utc_now()
    end
  end

  defp with_microsecond_precision(%DateTime{microsecond: {value, _precision}} = datetime) do
    %{datetime | microsecond: {value, 6}}
  end

  defp optional_string(event, key) do
    case Map.get(event, key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end
end
