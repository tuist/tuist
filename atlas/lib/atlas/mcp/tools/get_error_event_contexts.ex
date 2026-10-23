defmodule Atlas.MCP.Tools.GetErrorEventContexts do
  @moduledoc "Reads bounded tenant and feature-flag observations without exposing raw error payloads."

  use Atlas.MCP.Tool,
    name: "get_error_event_contexts",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string", "format" => "uuid"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "issue_id" => %{"type" => "string"},
        "service_project_id" => %{"type" => "string"},
        "event_contexts" => %{"type" => "array", "maxItems" => 20, "items" => %{"type" => "object"}}
      },
      "required" => ~w(issue_id service_project_id event_contexts),
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Errors
  alias Atlas.MCP.Tool

  @tenant_keys ~w(auth_account_id auth_project_id auth_account_handle selected_account_id selected_project_id selected_account_handle selected_project_handle)

  @impl EMCP.Tool
  def description do
    "Fetch tenant and feature-flag context from up to 20 recent events for an Engineering error issue. Requires engineering:read. " <>
      "Exposes no request bodies or stack arguments. service_project_id identifies the Engineering service, " <>
      "not the customer's selected_project_id. This is a bounded sample, not an error rate or evidence of causation."
  end

  def execute(conn, %{"id" => id}) do
    with :ok <- Tool.authorize_scope(conn, "engineering:read", "Error event context"),
         {:ok, issue} <- Errors.fetch_issue(id) do
      contexts = id |> Errors.list_events_for_issue(limit: 20) |> Enum.map(&event_context/1)
      {:ok, %{"issue_id" => issue.id, "service_project_id" => issue.project_id, "event_contexts" => contexts}}
    else
      {:error, :not_found} -> {:error, "Error issue not found."}
      error -> error
    end
  end

  defp event_context(event) do
    payload = event.payload || %{}
    tags = scalar_context(payload["tags"])
    extra = scalar_context(payload["extra"])

    %{
      event_id: event.event_id,
      timestamp: event.timestamp,
      environment: event.environment,
      release: event.release,
      context: Map.merge(extra, tags)
    }
  end

  defp scalar_context(context) when is_map(context) do
    context
    |> Enum.filter(fn {key, value} ->
      is_binary(key) and byte_size(key) <= 128 and (key in @tenant_keys or String.starts_with?(key, "feature_flag.")) and
        (is_boolean(value) or is_integer(value) or (is_binary(value) and byte_size(value) <= 256))
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.take(64)
    |> Map.new()
  end

  defp scalar_context(_context), do: %{}
end
