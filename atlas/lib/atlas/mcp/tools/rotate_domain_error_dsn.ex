defmodule Atlas.MCP.Tools.RotateDomainErrorDsn do
  @moduledoc "Rotates the Sentry-compatible DSN for a (project, domain) pair."

  use Atlas.MCP.Tool,
    name: "rotate_domain_error_dsn",
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
      "properties" => %{"key" => %{"type" => "object"}},
      "required" => ["key"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.EngineeringSerializers

  @impl EMCP.Tool
  def description,
    do:
      "Invalidate the current Sentry-compatible DSN for a (project, domain) pair and return the freshly minted replacement."

  def execute(conn, %{"project_id" => project_id, "domain_id" => domain_id}) do
    user = Tool.current_user(conn)

    with {:ok, project} <- Projects.fetch_visible_project(project_id, user),
         {:ok, domain} <- Domains.fetch_visible_domain(domain_id, user),
         :ok <- ensure_linked(project, domain),
         {:ok, key} <- Errors.rotate_domain_key(project, domain) do
      {:ok, %{"key" => EngineeringSerializers.project_key(key)}}
    else
      {:error, :not_found} -> {:error, "Project or domain not found."}
      {:error, :not_linked} -> {:error, "Domain is not linked to project."}
      {:error, _} -> {:error, "DSN rotation failed."}
    end
  end

  defp ensure_linked(project, domain) do
    if Enum.any?(domain.projects || [], &(&1.id == project.id)),
      do: :ok,
      else: {:error, :not_linked}
  end
end
