defmodule Atlas.MCP.Tools.DeleteEmailAudience do
  @moduledoc """
  Deletes an unused manual email audience.
  """

  use Atlas.MCP.Tool,
    name: "delete_email_audience",
    schema: %{
      "type" => "object",
      "required" => ["audience_id"],
      "properties" => %{
        "audience_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "deleted" => %{"type" => "boolean"},
        "audience" => Atlas.MCP.Serializers.GTMEmail.audience_schema()
      },
      "required" => ["deleted", "audience"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Delete a manual email audience that has no broadcast history. Dynamic audiences and audiences with broadcasts are retained."
  end

  def execute(conn, %{"audience_id" => id}) do
    case GTM.get_email_audience(id) do
      nil ->
        {:error, "Email audience not found."}

      audience ->
        case GTM.delete_email_audience(audience, Tool.current_user(conn)) do
          {:ok, deleted} ->
            {:ok, %{deleted: true, audience: GTMEmail.audience(deleted)}}

          {:error, :has_broadcasts} ->
            {:error, "Email audiences with broadcast history cannot be deleted."}

          {:error, :dynamic_audience} ->
            {:error, "Dynamic email audiences cannot be deleted."}
        end
    end
  end
end
