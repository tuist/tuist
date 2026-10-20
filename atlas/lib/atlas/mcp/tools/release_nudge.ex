defmodule Atlas.MCP.Tools.ReleaseNudge do
  @moduledoc "Releases a claimed nudge back to the queue so another operator can pick it up."

  use Atlas.MCP.Tool,
    name: "release_nudge",
    schema: %{
      "type" => "object",
      "required" => ["nudge_id"],
      "properties" => %{"nudge_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Nudges.nudge_schema()

  alias Atlas.MCP.Serializers.Nudges, as: NudgeSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Nudges

  @impl EMCP.Tool
  def description do
    "Release a claimed nudge back to the queue. Ownership is cleared so another operator can claim and send it."
  end

  def execute(conn, %{"nudge_id" => nudge_id}) when is_binary(nudge_id) do
    with :ok <- Tool.authorize_scope(conn, "accounts:write", "Nudge tools"),
         {:ok, nudge} <- Nudges.release(nudge_id) do
      {:ok, NudgeSerializer.nudge(nudge)}
    else
      {:error, :not_found} -> {:error, "Nudge not found: #{nudge_id}"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, reason} -> {:error, "Could not release the nudge: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "nudge_id is required."}
end
