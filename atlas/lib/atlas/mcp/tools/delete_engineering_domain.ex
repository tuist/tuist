defmodule Atlas.MCP.Tools.DeleteEngineeringDomain do
  @moduledoc "Deletes an engineering domain."

  use Atlas.MCP.Tool,
    name: "delete_engineering_domain",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted_domain" => %{"type" => "object"}},
      "required" => ["deleted_domain"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Delete an Engineering domain."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        snapshot = EngineeringSerializers.domain(domain)

        case Domains.delete_domain(domain) do
          {:ok, _} -> {:ok, %{"deleted_domain" => snapshot}}
          {:error, changeset} -> {:error, "Could not delete domain: #{Tool.format_changeset_errors(changeset)}"}
        end

      {:error, :not_found} ->
        {:error, "Domain not found."}
    end
  end
end
