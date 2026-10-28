defmodule Atlas.MCP.Tools.GetAuditActivity do
  @moduledoc """
  Gets a single audit activity for executive users.
  """

  use Atlas.MCP.Tool,
    name: "get_audit_activity",
    schema: %{
      "type" => "object",
      "required" => ["activity_id"],
      "properties" => %{
        "activity_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "activity" => Atlas.Audit.serialize_schema()
      },
      "required" => ["activity"],
      "additionalProperties" => false
    }

  alias Atlas.Audit
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Get one Atlas audit activity by id. Only available to admins."

  def execute(conn, %{"activity_id" => id}) when is_binary(id) do
    with :ok <- Tool.authorize_scope(conn, "audit:read", "Audit tools") do
      case Audit.get_activity(id) do
        nil -> {:error, "Audit activity not found: #{id}"}
        activity -> {:ok, %{activity: Audit.serialize(activity)}}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "activity_id is required."}
end
