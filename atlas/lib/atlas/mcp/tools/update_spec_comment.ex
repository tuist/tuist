defmodule Atlas.MCP.Tools.UpdateSpecComment do
  @moduledoc "Updates one of the caller's spec comments."

  use Atlas.MCP.Tool,
    name: "update_spec_comment",
    schema: %{
      "type" => "object",
      "required" => ["comment_id", "body"],
      "properties" => %{
        "comment_id" => %{"type" => "string"},
        "body" => %{"type" => "string"}
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
  def description, do: "Update one of the caller's spec comments."

  def execute(conn, %{"comment_id" => comment_id} = args) do
    user = Tool.current_user(conn)

    case fetch_comment(comment_id) do
      {:ok, comment} ->
        with {:ok, spec} <- Specs.fetch_visible_spec_by_reference(comment.spec_id, user),
             {:ok, _updated} <- Specs.update_comment(comment, Map.take(args, ["body"]), user) do
          {:ok, %{"spec" => SpecSerializers.spec(Specs.get_spec!(spec.id))}}
        else
          {:error, :not_found} ->
            {:error, "Spec comment not found."}

          {:error, :unauthorized} ->
            {:error, "You can only update your own spec comments."}

          {:error, changeset} ->
            {:error, "Could not update comment: #{Tool.format_changeset_errors(changeset)}"}
        end

      :error ->
        {:error, "Spec comment not found."}
    end
  end

  defp fetch_comment(comment_id) do
    {:ok, Specs.get_comment!(comment_id)}
  rescue
    Ecto.NoResultsError -> :error
    Ecto.Query.CastError -> :error
  end
end
