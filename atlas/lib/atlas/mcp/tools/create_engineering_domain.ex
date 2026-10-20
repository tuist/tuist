defmodule Atlas.MCP.Tools.CreateEngineeringDomain do
  @moduledoc "Creates an engineering domain."

  use Atlas.MCP.Tool,
    name: "create_engineering_domain",
    schema: %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
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
  def description, do: "Create a reusable Engineering domain."

  def execute(_conn, args) do
    attrs = Map.take(args, ["name", "description", "visibility"])

    case Domains.create_domain(attrs) do
      {:ok, domain} ->
        {:ok, %{"domain" => EngineeringSerializers.domain(Domains.get_domain!(domain.id))}}

      {:error, changeset} ->
        {:error, "Could not create domain: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
