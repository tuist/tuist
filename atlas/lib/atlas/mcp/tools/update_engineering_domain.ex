defmodule Atlas.MCP.Tools.UpdateEngineeringDomain do
  @moduledoc "Updates an engineering domain."

  use Atlas.MCP.Tool,
    name: "update_engineering_domain",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"domain" => %{"type" => "object"}},
      "required" => ["domain"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Update an Engineering domain."

  def execute(conn, %{"id" => id} = args) do
    user = Tool.current_user(conn)
    attrs = Map.take(args, ["name", "description", "visibility"])

    with {:ok, domain} <- Domains.fetch_visible_domain(id, user),
         {:ok, updated} <- Domains.update_domain(domain, attrs) do
      {:ok, %{"domain" => EngineeringSerializers.domain(Domains.get_domain!(updated.id))}}
    else
      {:error, :not_found} -> {:error, "Domain not found."}
      {:error, changeset} -> {:error, "Could not update domain: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
