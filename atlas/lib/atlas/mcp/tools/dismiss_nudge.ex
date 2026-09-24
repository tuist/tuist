defmodule Atlas.MCP.Tools.DismissNudge do
  @moduledoc "Dismisses a nudge with a required reason."

  use Atlas.MCP.Tool,
    name: "dismiss_nudge",
    schema: %{
      "type" => "object",
      "required" => ["nudge_id", "reason"],
      "properties" => %{
        "nudge_id" => %{"type" => "string"},
        "reason" => %{"type" => "string", "minLength" => 1, "maxLength" => 1_000},
        "mute_days" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 180,
          "description" => "Optional. Mutes future signals of the same kind on this account until this many days pass."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Nudges.nudge_schema()

  alias Atlas.MCP.Serializers.Nudges, as: NudgeSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Nudges

  @impl EMCP.Tool
  def description do
    "Dismiss a nudge with a required reason. Optional mute_days snoozes future firings for that number of days."
  end

  def execute(conn, %{"nudge_id" => nudge_id, "reason" => reason} = args)
      when is_binary(nudge_id) and is_binary(reason) and reason != "" do
    with :ok <- Tool.authorize_scope(conn, "accounts:write", "Nudge tools"),
         {:ok, nudge} <- Nudges.dismiss(nudge_id, attrs_from(args, reason)) do
      {:ok, NudgeSerializer.nudge(nudge)}
    else
      {:error, :not_found} -> {:error, "Nudge not found: #{nudge_id}"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, reason} -> {:error, "Could not dismiss the nudge: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "nudge_id and reason are required."}

  defp attrs_from(args, reason) do
    base = %{dismissed_reason: reason}

    case Map.get(args, "mute_days") do
      days when is_integer(days) and days in 1..180 ->
        until = DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)
        Map.put(base, :dismissed_until, until)

      _ ->
        base
    end
  end
end
