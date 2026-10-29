defmodule Atlas.MCP.Tools.ListEngineeringProjects do
  @moduledoc "Lists engineering projects tracked by Atlas."

  use Atlas.MCP.Tool,
    name: "list_engineering_projects",
    schema: %{
      "type" => "object",
      "properties" => %{},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "projects" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "description" => %{"type" => ["string", "null"]},
              "visibility" => %{"type" => "string"}
            },
            "required" => ["id", "name", "description", "visibility"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["projects"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List Engineering projects."

  def execute(conn, _args) do
    user = Tool.current_user(conn)
    projects = Projects.list_visible_projects(user)

    {:ok,
     %{
       "projects" =>
         Enum.map(projects, fn p ->
           %{
             "id" => p.id,
             "name" => p.name,
             "description" => p.description,
             "visibility" => to_string(p.visibility)
           }
         end)
     }}
  end
end
