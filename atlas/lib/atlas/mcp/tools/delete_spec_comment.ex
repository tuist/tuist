defmodule Atlas.MCP.Tools.DeleteSpecComment do
  @moduledoc "Deletes one of the caller's spec comments."

  use Atlas.MCP.Tool,
    name: "delete_spec_comment",
    schema: %{
      "type" => "object",
      "required" => ["comment_id"],
      "properties" => %{
        "comment_id" => %{"type" => "string"}
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
  def description, do: "Delete one of the caller's spec comments."

  def execute(conn, %{"comment_id" => comment_id}) do
    user = Tool.current_user(conn)

    case fetch_comment(comment_id) do
      {:ok, comment} ->
        with {:ok, spec} <- Specs.fetch_visible_spec_by_reference(comment.spec_id, user),
             {:ok, _deleted} <- Specs.delete_comment(comment, user) do
          {:ok, %{"spec" => SpecSerializers.spec(Specs.get_spec!(spec.id))}}
        else
          {:error, :not_found} ->
            {:error, "Spec comment not found."}

          {:error, :unauthorized} ->
            {:error, "You can only delete your own spec comments."}
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
