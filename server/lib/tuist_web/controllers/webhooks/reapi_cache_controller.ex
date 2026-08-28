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

      projects_map =
        events
        |> Enum.filter(&is_map/1)
        |> Enum.map(&"#{&1["account_handle"]}/#{&1["project_handle"]}")
        |> Enum.uniq()
        |> Projects.projects_by_full_handles()

      cache_events =
        events
        |> Enum.map(fn event ->
          with %{
                 "account_handle" => account_handle,
                 "project_handle" => project_handle,
                 "client_kind" => client_kind,
                 "operation" => operation,
                 "outcome" => outcome,
                 "action_digest" => action_digest,
                 "size" => size,
                 "duration_ms" => duration_ms
               } <- event,
               %{id: project_id, build_system: :bazel} <- Map.get(projects_map, "#{account_handle}/#{project_handle}"),
               true <-
                 valid_event?(
                   client_kind,
                   operation,
                   outcome,
                   action_digest,
                   size,
                   duration_ms,
                   Map.get(event, "observed_at_ms")
                 ) do
            %{
              client_kind: client_kind,
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
            }
          else
            nil ->
              Logger.warning("Project not found for Remote Execution API cache event")
              nil

            _ ->
              Logger.warning("Invalid Remote Execution API cache event")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      ReapiCache.create_cache_events(cache_events)

      conn
      |> put_status(:accepted)
      |> json(%{})
      |> halt()
    end
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end

  defp valid_event?(client_kind, operation, outcome, action_digest, size, duration_ms, observed_at_ms) do
    is_binary(client_kind) and operation in ["action_cache", "cas"] and
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
