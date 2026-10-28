defmodule Atlas.MCP.Tools.UpdateSpec do
  @moduledoc "Updates a spec after checking the expected revision."

  use Atlas.MCP.Tool,
    name: "update_spec",
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        },
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
        "engineering_project_id" => %{"type" => "string"},
        "visibility" => %{"type" => "string", "enum" => ["public", "private"]},
        "domain_ids" => %{
          "type" => "array",
          "items" => %{"type" => "string"}
        },
        "expected_revision" => %{"type" => "integer"}
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
  def description, do: "Update a spec. Authenticated operators only."

  def execute(conn, %{"id" => id, "expected_revision" => expected_revision} = args) do
    user = Tool.current_user(conn)

    case Specs.fetch_visible_spec_by_reference(id, user) do
      {:ok, %{lock_version: ^expected_revision} = spec} ->
        update(spec, user, args)

      {:ok, spec} ->
        {:error, "Spec revision is stale. Current revision is #{spec.lock_version}."}

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end

  defp update(spec, user, args) do
    attrs =
      Map.take(args, [
        "title",
        "body",
        "summary",
        "status",
        "engineering_project_id",
        "visibility",
        "domain_ids"
      ])

    case Specs.update_spec(spec, attrs, user) do
      {:ok, updated} ->
        {:ok, %{"spec" => SpecSerializers.spec(Specs.get_spec!(updated.id))}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can update specs."}

      {:error, :locked} ->
        {:error, "This spec is being written by another request. Try again in a moment."}

      {:error, changeset} ->
        {:error, "Could not update spec: #{Tool.format_changeset_errors(changeset)}"}
    end
  end
end
