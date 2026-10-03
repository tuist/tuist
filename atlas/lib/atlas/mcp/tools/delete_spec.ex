defmodule Atlas.MCP.Tools.DeleteSpec do
  @moduledoc "Deletes a spec after checking the expected revision."

  use Atlas.MCP.Tool,
    name: "delete_spec",
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        },
        "expected_revision" => %{
          "type" => "integer",
          "description" => "Revision returned by get_spec or list_specs."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted_spec" => Atlas.MCP.Tools.SpecSerializers.spec_schema()},
      "required" => ["deleted_spec"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description, do: "Delete a spec. Authenticated operators only."

  def execute(conn, %{"id" => id, "expected_revision" => expected_revision}) do
    user = Tool.current_user(conn)

    if Specs.can_create?(user) do
      delete(user, id, expected_revision)
    else
      {:error, "Only authenticated operators can delete specs."}
    end
  end

  defp delete(user, id, expected_revision) do
    case Specs.fetch_visible_spec_by_reference(id, user) do
      {:ok, %{lock_version: ^expected_revision} = spec} ->
        deleted = SpecSerializers.spec(spec)

        case Specs.delete_spec(spec, user) do
          {:ok, _spec} ->
            {:ok, %{"deleted_spec" => deleted}}

          {:error, :unauthorized} ->
            {:error, "Only authenticated operators can delete specs."}

          {:error, :stale} ->
            {:error, "Spec revision is stale. Refresh and try again."}

          {:error, changeset} ->
            {:error, "Could not delete spec: #{Tool.format_changeset_errors(changeset)}"}
        end

      {:ok, spec} ->
        {:error, "Spec revision is stale. Current revision is #{spec.lock_version}."}

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end
end
