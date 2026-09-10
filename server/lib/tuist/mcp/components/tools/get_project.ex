defmodule Tuist.MCP.Components.Tools.GetProject do
  @moduledoc """
  Get a project's dashboard configuration.
  """

  use Tuist.MCP.Tool,
    name: "get_project",
    title: "Get Project",
    read_only_hint: true,
    authorize: [action: :read, category: :project],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        }
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "full_handle" => %{"type" => "string"},
        "default_branch" => %{"type" => "string"},
        "visibility" => %{"type" => "string", "enum" => ["private", "public"]},
        "build_system" => %{"type" => "string", "enum" => ["xcode", "gradle", "bazel"]},
        "repository_url" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "full_handle", "default_branch", "visibility", "build_system", "repository_url"],
      "additionalProperties" => false
    }

  alias Tuist.Projects

  @impl EMCP.Tool
  def description,
    do:
      "Get a project's dashboard configuration. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, _args, project) do
    {:ok,
     %{
       id: project.id,
       full_handle: "#{project.account.name}/#{project.name}",
       default_branch: project.default_branch,
       visibility: to_string(project.visibility),
       build_system: to_string(project.build_system),
       repository_url: Projects.get_repository_url(project)
     }}
  end
end
