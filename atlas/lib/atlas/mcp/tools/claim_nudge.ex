defmodule Atlas.MCP.Tools.ClaimNudge do
  @moduledoc "Claims an open nudge on behalf of the calling user."

  use Atlas.MCP.Tool,
    name: "claim_nudge",
    schema: %{
      "type" => "object",
      "required" => ["nudge_id"],
      "properties" => %{"nudge_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Nudges.nudge_schema()

  alias Atlas.MCP.Serializers.Nudges, as: NudgeSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Nudges
  alias Atlas.Users
  alias Atlas.Users.User

  @impl EMCP.Tool
  def description do
    "Claim an open nudge. The current MCP user takes ownership; only the claimant can send or dismiss it."
  end

  def execute(conn, %{"nudge_id" => nudge_id}) when is_binary(nudge_id) do
    with :ok <- Tool.authorize_scope(conn, "accounts:write", "Nudge tools"),
         %User{} = actor <- current_user(conn),
         {:ok, nudge} <- Nudges.claim(nudge_id, actor) do
      {:ok, NudgeSerializer.nudge(nudge)}
    else
      nil -> {:error, "MCP user could not be resolved."}
      {:error, :not_found} -> {:error, "Nudge not found: #{nudge_id}"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, reason} -> {:error, "Could not claim the nudge: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "nudge_id is required."}

  defp current_user(conn) do
    case conn.assigns[:current_user] do
      %User{} = user -> user
      _ -> mcp_actor_from_email(conn)
    end
  end

  defp mcp_actor_from_email(conn) do
    case conn.assigns[:current_user_email] do
      email when is_binary(email) and email != "" -> Users.get_user_by_email(email)
      _ -> nil
    end
  end
end
