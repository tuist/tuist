defmodule Atlas.MCP.Tools.GetEngineeringDomain do
  @moduledoc "Fetches an engineering domain by id."

  use Atlas.MCP.Tool,
    name: "get_engineering_domain",
    schema: %{
      "type" => "object",
      "required" => ["id"],
      "properties" => %{"id" => %{"type" => "string"}},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "domain" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "name" => %{"type" => "string"},
            "description" => %{"type" => ["string", "null"]},
            "visibility" => %{"type" => "string"},
            "project_ids" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          "required" => ["id", "name", "description", "visibility", "project_ids"],
          "additionalProperties" => false
        }
      },
      "required" => ["domain"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Fetch an Engineering domain by id."

  def execute(conn, %{"id" => id}) do
    user = Tool.current_user(conn)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} ->
        {:ok,
         %{
           "domain" => %{
             "id" => domain.id,
             "name" => domain.name,
             "description" => domain.description,
             "visibility" => to_string(domain.visibility),
             "project_ids" => Enum.map(domain.projects, & &1.id)
           }
         }}

      {:error, :not_found} ->
        {:error, "Domain not found."}
    end
  end
end
