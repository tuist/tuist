defmodule Atlas.MCP.Tools.ListPeople do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_people",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "people" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "email" => %{"type" => "string"},
              "online" => %{"type" => "boolean"}
            },
            "required" => ["id", "name", "email", "online"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["people"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.Presence

  @impl EMCP.Tool
  def description, do: "List Atlas teammates and current availability, without reporting their browsing locations."

  def execute(conn, _args) do
    with :ok <- Tool.authorize_authenticated(conn, "People") do
      people = Presence.snapshot(Tool.current_user(conn)).people
      {:ok, %{people: Enum.map(people, &Map.take(&1, [:id, :name, :email, :online]))}}
    end
  end
end
