defmodule Atlas.MCP.Tools.UnlinkProjectDomain do
  @moduledoc "Removes a domain link from a project."

  use Atlas.MCP.Tool,
    name: "unlink_project_domain",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "domain_id"],
      "properties" => %{
        "project_id" => %{"type" => "string"},
        "domain_id" => %{"type" => "string"}
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "project" => %{"type" => "object"},
        "unlinked_domain" => %{"type" => "object"}
      },
      "required" => ["project", "unlinked_domain"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description, do: "Remove a domain link from a project."

  def execute(conn, %{"project_id" => project_id, "domain_id" => domain_id}) do
    user = Tool.current_user(conn)

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, domain} <- Domains.fetch_visible_domain(domain_id, user),
         :ok <- Projects.unlink_domain_from_project(project, domain.id) do
      {:ok,
       %{
         "project" => EngineeringSerializers.project(Projects.get_project!(project.id)),
         "unlinked_domain" => EngineeringSerializers.domain(domain)
       }}
    else
      {:error, :not_found} -> {:error, "Project or domain not found."}
    end
  end
end
