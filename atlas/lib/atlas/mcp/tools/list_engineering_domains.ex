defmodule Atlas.MCP.Tools.ListEngineeringDomains do
  @moduledoc "Lists engineering domains tracked by Atlas."

  use Atlas.MCP.Tool,
    name: "list_engineering_domains",
    schema: %{
      "type" => "object",
      "properties" => %{},
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "domains" => %{
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
      "required" => ["domains"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Domains
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List Engineering domains."

  def execute(conn, _args) do
    user = Tool.current_user(conn)
    domains = Domains.list_visible_domains(user)

    {:ok,
     %{
       "domains" =>
         Enum.map(domains, fn d ->
           %{
             "id" => d.id,
             "name" => d.name,
             "description" => d.description,
             "visibility" => to_string(d.visibility)
           }
         end)
     }}
  end
end
