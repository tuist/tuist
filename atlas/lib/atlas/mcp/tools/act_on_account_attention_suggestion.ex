defmodule Atlas.MCP.Tools.ActOnAccountAttentionSuggestion do
  @moduledoc "Records a decision on an account follow-up suggestion."

  use Atlas.MCP.Tool,
    name: "act_on_account_attention_suggestion",
    schema: %{
      "type" => "object",
      "required" => ["suggestion_id", "action"],
      "properties" => %{
        "suggestion_id" => %{"type" => "string"},
        "action" => %{"type" => "string", "enum" => ["done", "snooze", "dismiss"]},
        "note" => %{"type" => "string", "maxLength" => 1_000},
        "snooze_days" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 90,
          "description" => "Days to wait before re-delivering a snoozed suggestion. Defaults to 7."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.account_attention_suggestion_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Mark a follow-up suggestion done, snooze it, or dismiss it after the user explicitly chooses that action."
  end

  def execute(_conn, %{"suggestion_id" => id, "action" => action} = args) do
    with suggestion when not is_nil(suggestion) <- Accounts.get_account_attention_suggestion(id),
         {:ok, suggestion} <- perform(action, suggestion, args) do
      {:ok, AccountSerializer.account_attention_suggestion(suggestion)}
    else
      nil -> {:error, "Account attention suggestion not found: #{id}"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, reason} -> {:error, "Could not update the account attention suggestion: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "suggestion_id and action are required."}

  defp perform("done", suggestion, args), do: Accounts.action_account_attention_suggestion(suggestion, args["note"])

  defp perform("snooze", suggestion, args) do
    days = Map.get(args, "snooze_days", 7)

    if is_integer(days) and days in 1..90 do
      until = DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)
      Accounts.snooze_account_attention_suggestion(suggestion, until, args["note"])
    else
      {:error, :invalid_snooze_days}
    end
  end

  defp perform("dismiss", suggestion, args), do: Accounts.dismiss_account_attention_suggestion(suggestion, args["note"])

  defp perform(_action, _suggestion, _args), do: {:error, :unsupported_account_attention_action}
end
