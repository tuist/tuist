defmodule Atlas.MCP.Tools.CreateSpec do
  @moduledoc "Creates a spec bound to an engineering project."

  use Atlas.MCP.Tool,
    name: "create_spec",
    schema: %{
      "type" => "object",
      "required" => ["title", "body", "engineering_project_id"],
      "properties" => %{
        "title" => %{"type" => "string"},
        "body" => %{
          "type" => "string",
          "description" => "Spec body in Markdown. Fenced ```mermaid blocks render as diagrams."
        },
        "summary" => %{
          "type" => "string",
          "description" => "Short spec description for summaries and OpenGraph cards. Do not use em dashes."
        },
        "status" => %{"type" => "string"},
        "engineering_project_id" => %{
          "type" => "string",
          "description" => "Identifier of the engineering project the spec belongs to."
        },
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]},
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Domain identifiers to associate with the spec."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"spec" => Atlas.MCP.Tools.SpecSerializers.spec_schema()},
      "required" => ["spec"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description, do: "Create a spec. Authenticated operators only."

  def execute(conn, args) do
    attrs =
      args
      |> Map.take([
        "title",
        "body",
        "summary",
        "status",
        "engineering_project_id",
        "visibility",
        "domain_ids"
      ])
      |> Map.put_new("status", "draft")

    case Specs.create_spec(attrs, Tool.current_user(conn)) do
      {:ok, spec} ->
        spec = Specs.get_spec!(spec.id)
        {:ok, %{"spec" => SpecSerializers.spec(spec)}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can create specs."}

      {:error, :locked} ->
        {:error, "A spec write is currently in progress. Try again in a moment."}

      {:error, changeset} ->
        {:error, "Could not create spec: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
